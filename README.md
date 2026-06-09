# LazyJP

思考を中断させない日本語入力。ローマ字のまま書き続けると、AI が文脈を読んで非同期に日本語へ変換する。

## 概要

- ローマ字（またはピンイン混在）でタイプし続ける
- `Ctrl+m` でトリガー：現在行をバックグラウンドでエンジンに送信 → 改行して次の入力を継続
- 変換結果が返ってきたら自動的にローマ字行が日本語に置き換わる
- その間もユーザーは次の行をタイプし続けられる

## 構成

```
engine/   FastAPI 変換エンジン（Python）
lua/      Neovim プラグイン（Lua）
```

## セットアップ

### エンジンの起動

```sh
cd engine
pip install -r requirements.txt
uvicorn main:app --host 127.0.0.1 --port 8000
```

環境変数でモデルを設定する（LiteLLM 経由で任意のプロバイダを使用可能）：

```sh
export OPENAI_API_KEY=sk-...
# または
export ANTHROPIC_API_KEY=sk-ant-...
```

### Neovim プラグインのインストール

[lazy.nvim](https://github.com/folke/lazy.nvim) を使っている場合：

```lua
{
  "cympfh/LazyJP",
  config = function()
    require("lazyjp").setup({
      engine_url = "http://localhost:8000",  -- default
      style = "casual",                      -- casual / formal
      languages = { "ja" },                  -- ja / zh / en
    })
  end,
}
```

### キーマップのカスタマイズ

デフォルトのトリガーは `Ctrl+m`（Insert モード）。変更したい場合：

```lua
require("lazyjp").setup({})
-- デフォルトキーマップを上書き
vim.keymap.set("i", "<C-j>", function()
  require("lazyjp").trigger()
end)
```

## 動作の詳細

1. Insert モードで `Ctrl+m` を押す
2. 現在行が空 → 通常の改行のみ
3. 現在行に内容あり → エンジンに非同期送信 + 改行挿入
4. エンジンが変換結果を返す → ローマ字行を日本語に置き換え
5. 行を編集した場合 → 変換はキャンセルされ、ローマ字のまま残る

コンテキストとして直前2つの変換済み結果がエンジンに渡されるため、文章の流れを維持した変換が行われる。

## エンジン API

### POST /convert

```json
{
  "input_text": "knnchw、nh",
  "style": "casual",
  "languages": ["ja"],
  "context": ["前の文1", "前の文2"]
}
```

```json
{
  "result_text": "こんにちは、你好",
  "cached": false
}
```

キャッシュは SQLite に無期限永続化される。同一入力は LLM を呼ばず即座に返す。
