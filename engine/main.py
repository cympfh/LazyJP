import hashlib
import json
import os
import sqlite3
import subprocess
import sys

import click
from litellm import completion

__version__ = "0.1.0"

# ---- LLM config ----


def _load_llm_config() -> dict:
    result = subprocess.run(["llm-config", "-r", "none"], capture_output=True)
    return json.loads(result.stdout.decode())


# ---- SQLite cache ----

DB_PATH = os.environ.get(
    "LAZYJP_CACHE_DB", os.path.expanduser("~/.cache/lazyjp/cache.db")
)


def _init_db(conn: sqlite3.Connection):
    conn.execute("""
        CREATE TABLE IF NOT EXISTS conversion_cache (
            cache_key    TEXT PRIMARY KEY,
            input_text   TEXT NOT NULL,
            style_hash   TEXT NOT NULL,
            language_decl TEXT NOT NULL,
            result_text  TEXT NOT NULL,
            created_at   TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            last_used_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    """)
    conn.commit()


def get_db() -> sqlite3.Connection:
    db_dir = os.path.dirname(DB_PATH)
    if db_dir:
        os.makedirs(db_dir, exist_ok=True)
    db = sqlite3.connect(DB_PATH)
    _init_db(db)
    return db


def _cache_key(input_text: str, style_hash: str, language_decl: str) -> str:
    raw = f"{input_text}\x00{style_hash}\x00{language_decl}"
    return hashlib.sha256(raw.encode()).hexdigest()


def cache_get(db: sqlite3.Connection, cache_key: str) -> str | None:
    row = db.execute(
        "SELECT result_text FROM conversion_cache WHERE cache_key = ?",
        (cache_key,),
    ).fetchone()
    if row:
        db.execute(
            "UPDATE conversion_cache SET last_used_at = CURRENT_TIMESTAMP WHERE cache_key = ?",
            (cache_key,),
        )
        db.commit()
        return row[0]
    return None


def cache_set(
    db: sqlite3.Connection,
    cache_key: str,
    input_text: str,
    style_hash: str,
    language_decl: str,
    result_text: str,
):
    db.execute(
        """
        INSERT OR REPLACE INTO conversion_cache
            (cache_key, input_text, style_hash, language_decl, result_text)
        VALUES (?, ?, ?, ?, ?)
        """,
        (cache_key, input_text, style_hash, language_decl, result_text),
    )
    db.commit()


# ---- Prompt ----

STYLE_PROMPTS = {
    "casual": "カジュアルで自然な日本語",
    "formal": "丁寧で正式な日本語",
}

LANG_NAMES = {
    "ja": "日本語",
    "zh": "中国語",
    "en": "英語",
}


def _build_system_prompt(style: str, languages: list[str]) -> str:
    style_desc = STYLE_PROMPTS.get(style, STYLE_PROMPTS["casual"])
    lang_desc = "・".join(LANG_NAMES.get(lang, lang) for lang in languages)
    return f"""<role>あなたはローマ字・ピンイン混在テキストを補完・修正するアシスタントです。
これは翻訳ではありません。
</role>

<task>
ユーザーが入力するテキストはローマ字（日本語の音写）やピンイン（中国語の音写）、
および英語・中国語などの単語を混在させた文字列です。
これを {lang_desc} の {style_desc} として自然に読めるよう補完・修正してください。
</task>

<rules>
- 補完・修正後のテキストのみを出力する（説明・コメント不要）
- 英語・中国語などの外来語・専門用語はそのまま残す（日本語に訳さない）
- 元のテキストの意図・ニュアンスを保つ
- コンテキストが提供された場合は文章の流れを維持する
- 記号・句読点は適切に補完する
</rules>

<samples>
補完・修正例:

入力: wo jintian hen lei
出力: 我今天很累
NOTE: 翻訳はしない。中国語は中国語

入力: kyou ha ii tenki desune
出力: 今日はいい天気ですね

入力: ashitahayakuokitemiru
出力: 明日早く起きてみる
NOTE: ローマ字は日本語。スペースがあるとは限らない

入力: errorga detanode debugshitemiru
出力: error が出たので debug してみる
NOTE: 英語が混ざることもある。英文と和文の間にはスペースがあると望ましい

入力: kono function ha input wo return suru
出力: この function は input を return する
NOTE: 英語が混ざることもある。英文と和文の間にはスペースがあると望ましい

入力: kono lanzhou lamian ha oishikatta,matakonoomiseni koyou
出力: この兰州拉面はおいしかった、またこのお店に来よう
NOTE: 中国語の固有名詞は簡体字で補完する

入力: kino no meeting ha muzukashikatta, demo ii idea ga deta
出力: 昨日の meeting は難しかったけど、いい idea が出た

入力: knnchw,konobgwo mitekdsai
出力: こんにちは、この bug を見てください

入力: saiak, mata shppai shta, korha muzukashi, tugiha ganbaru.
出力: 最悪、また失敗した、これは難しい、次は頑張る。

入力: kinonousiawasede new feature wo implementshitakedo,sositara bugga detesstk
出力: 昨日の打合せで new feature を implement したけど、そしたら bug が出て最悪
</samples>
"""


def _style_hash(style: str, languages: list[str]) -> str:
    prompt = _build_system_prompt(style, languages)
    return hashlib.sha256(prompt.encode()).hexdigest()[:16]


# ---- LLM call ----


def _llm_convert(
    input_text: str,
    style: str,
    languages: list[str],
    context: list[str],
    llm_config: dict,
) -> str:
    system_prompt = _build_system_prompt(style, languages)
    messages = [{"role": "system", "content": system_prompt}]

    if context:
        ctx_text = "\n".join(context)
        messages.append(
            {
                "role": "user",
                "content": f"[直前の文章（文脈として参照）]\n{ctx_text}",
            }
        )
        messages.append(
            {
                "role": "assistant",
                "content": "わかりました。文脈を踏まえて変換します。",
            }
        )

    messages.append({"role": "user", "content": input_text})

    cfg = llm_config
    model = f"{cfg['provider']}/{cfg['model']}"
    extra: dict = {}
    if cfg.get("reasoning_effort") and cfg["reasoning_effort"] != "none":
        extra["reasoning_effort"] = cfg["reasoning_effort"]

    result = completion(model=model, messages=messages, **extra)
    return result.choices[0].message.content.strip()


# ---- CLI ----


@click.group()
def cli():
    pass


@cli.command()
@click.option("--style", default="casual", show_default=True)
@click.option("--languages", default="ja,en,zh", show_default=True, help="カンマ区切り")
@click.option("--context", multiple=True, help="直前の変換結果（複数回指定可）")
@click.option("--verbose", "-v", is_flag=True, default=False, help="詳細ログを stderr に出力")
def convert(style: str, languages: str, context: tuple[str, ...], verbose: bool):
    """input_text を stdin から読み取り、変換結果を stdout に出力する。"""
    def log(msg: str):
        if verbose:
            click.echo(f"[lazyjp] {msg}", err=True)

    input_text = sys.stdin.read()
    lang_list = [lang.strip() for lang in languages.split(",") if lang.strip()]

    log(f"input: {input_text.strip()!r}")
    log(f"style: {style}, languages: {lang_list}, context: {list(context)}")

    if not input_text.strip():
        click.echo(input_text, nl=False)
        return

    db = get_db()
    sh = _style_hash(style, lang_list)
    lang_decl = ",".join(sorted(lang_list))
    key = _cache_key(input_text.strip(), sh, lang_decl)

    cached = cache_get(db, key)
    if cached is not None:
        db.close()
        log(f"cache hit => {cached!r}")
        click.echo(cached)
        return

    log("cache miss, calling LLM...")
    try:
        llm_config = _load_llm_config()
        log(f"llm config: {llm_config.get('provider')}/{llm_config.get('model')}")
        result = _llm_convert(input_text, style, lang_list, list(context), llm_config)
    except Exception as e:
        db.close()
        click.echo(f"LLM error: {e}", err=True)
        sys.exit(1)

    log(f"result: {result!r}")
    cache_set(db, key, input_text.strip(), sh, lang_decl, result)
    db.close()
    click.echo(result)


@cli.command()
def version():
    """バージョンを表示する。"""
    click.echo(__version__)


@cli.command()
def clear():
    """キャッシュ DB を削除する。"""
    if os.path.exists(DB_PATH):
        os.remove(DB_PATH)
        click.echo(f"Removed: {DB_PATH}")
    else:
        click.echo(f"Not found: {DB_PATH}")


if __name__ == "__main__":
    cli()
