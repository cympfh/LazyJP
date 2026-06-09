@CLAUDE TODO List

## [x] エンジンのスタブを実装する [2026-06-09 完了]

まだオプションを受け取ってダミーを返すだけでOK
`engine/main.py` に FastAPI スタブ実装。`/convert` はリクエストをそのまま返す。

## [x] nvim プラグインのスタブで実装する [2026-06-09 完了]

本プロジェクトは
https://github.com/cympfh/LazyJP
で管理されてる。
簡単にインストールでくるように
`lua/lazyjp/init.lua` + `plugin/lazyjp.lua` で lazy.nvim からインストール可能な構造を実装。

## [x] README を書く [2026-06-09 完了]

実装済みだと仮定して先に README を書いてみる。

## [x] エンジンの実装 [2026-06-09 完了]

litellm の使いかたを知るためにまず ~/bin/translate を読む
本格的に実装する
`engine/main.py` を本格実装。llm-config 経由でプロバイダ設定、SQLite キャッシュ、LiteLLM 呼び出し。

## [x] nvim プラグインの実装 [2026-06-09 完了]

本格的に実装する
`M.trigger()` をパブリック API として公開。TextChanged でキャンセル検知、context 2件管理を完成。

## [x] プロンプトにサンプルを書く [2026-06-09 完了]

精度向上のために few-shot で変換前後を入れる

- ふつうのローマ字だけ (2件)
- 英語とローマ字の混じったもの (2件)
- 英語と中国語（拼音）とローマ字の混じったもの (2件)
- ノイジーな拼音とノイジーなローマ字の混じったもの (2件)
- 全部混ざった一番難しいもの

先に変換後を考えてから、変換前を考えるとやりやすいかも
スペースあり・なし交互、中国語のみサンプルを先頭に追加。「翻訳ではなく補完・修正」と明記。

## [x] デフォルトで ja+en+zh にする [2026-06-09 完了]

`engine/main.py` の `ConvertRequest.languages` と `lua/lazyjp/init.lua` の `M.config.languages` を `["ja", "en", "zh"]` に変更。

## [x] エンジンをサーバにするのをやめて CLI コマンドにする [2026-06-09 完了]

- Unix 哲学に基づく「ふつうの小さな」CLI コマンドにする
    - Python ライブラリの Click を使う
- nvim 側は vim.fn.jobstart() で非同期に呼び出す
- `lazyjp convert`: stdin JSON → stdout JSON
- DB パスを `~/.cache/lazyjp/cache.db` に変更
- nvim プラグインは `M.config.cmd = "lazyjp"` で呼び出す
