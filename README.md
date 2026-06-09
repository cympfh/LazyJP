# LazyJP

思考を中断させない日本語入力。ローマ字のまま書き続けると、AI が文脈を読んで非同期に日本語へ変換する。

## 概要

- ローマ字（またはピンイン混在）でタイプし続ける
- `Ctrl+m` でトリガー：現在行をバックグラウンドでエンジンに送信 → 改行して次の入力を継続
- 変換結果が返ってきたら自動的にローマ字行が日本語に置き換わる
- その間もユーザーは次の行をタイプし続けられる

## 構成

```
engine/   CLI 変換エンジン（Python + Click）
lua/      Neovim プラグイン（Lua）
```

## セットアップ

### エンジンのインストール

```sh
cd engine
pip install -r requirements.txt
```

LLM プロバイダの設定は `llm-config` コマンド経由で行う（LiteLLM 対応の任意プロバイダが使用可能）。

### CLI コマンド

```sh
# 変換（input_text は stdin から）
echo "kyou ha ii tenki desune" | lazyjp convert

# オプション
echo "..." | lazyjp convert --style formal --languages ja,en

# キャッシュ削除
lazyjp clear

# バージョン確認
lazyjp version
```

キャッシュは `~/.cache/lazyjp/cache.db`（SQLite）に無期限永続化される。同一入力は LLM を呼ばず即座に返す。

### Neovim プラグインのインストール

[lazy.nvim](https://github.com/folke/lazy.nvim) を使っている場合：

```lua
{
  "cympfh/LazyJP",
  config = function()
    require("lazyjp").setup({
      cmd = "lazyjp",       -- default: CLI コマンドのパス
      style = "casual",     -- casual / formal
      languages = { "ja", "en", "zh" },
    })
  end,
}
```

### キーマップのカスタマイズ

デフォルトのトリガーは `Ctrl+m`（Insert モード）。変更したい場合：

```lua
require("lazyjp").setup({})
vim.keymap.set("i", "<C-j>", function()
  require("lazyjp").trigger()
end)
```

## 動作の詳細

1. Insert モードで `Ctrl+m` を押す
2. 現在行が空 → 通常の改行のみ
3. 現在行に内容あり → `lazyjp convert` を非同期起動（stdin にテキストを渡す）+ 改行挿入
4. 変換結果が返ってきたら行が未編集であればローマ字行を日本語に置き換え
5. 行を編集した場合 → 変換はキャンセルされ、ローマ字のまま残る

コンテキストとして直前2つの変換済み結果が `--context` オプションで渡されるため、文章の流れを維持した変換が行われる。
