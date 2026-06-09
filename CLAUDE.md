# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 概要

LazyJP は「思考を中断させない日本語入力」を実現するプロジェクト。ローマ字（およびピンイン混在）をタイプし続け、AI が文脈を理解して非同期に自然な日本語へ変換する。

## アーキテクチャ

```
[Neovim プラグイン]
      ↓ HTTP 非同期
[変換エンジン (FastAPI + LiteLLM + SQLite)]
      ↓ 必要に応じて
[任意の LLM プロバイダ]
```

エンジンとプラグインは完全分離。エンジンは独立した HTTP サービス、プラグインは薄いクライアント。

### エンジン（`spec/LazyJP_02_エンジン仕様.md`）

- **スタック**: Python + FastAPI + LiteLLM + SQLite
- **主要エンドポイント**: `POST /convert`
  - リクエスト: `input_text`, `style`, `languages`
  - レスポンス: `result_text`, `cached`
- **キャッシュ**: SQLite (`cache.db`) に無期限永続化。キャッシュキーは `(input_text 正規化, style_hash, language_decl)` の3要素。コンテキストはキャッシュキーに含めない。

### Neovim プラグイン（`spec/LazyJP_03_プラグイン仕様.md`）

- **トリガー**: デフォルト `Ctrl+m`（ユーザーが `vim.keymap.set` で変更可能）
- **動作フロー**:
  1. `Ctrl+m` で現在行をエンジンに非同期送信 + 改行挿入
  2. 行を「変換待ちリスト」に追加（行番号 + ハッシュで追跡）
  3. 結果受信時、行が未編集なら元のローマ字行を削除して日本語に置換
  4. 編集済みならキャンセル（無視）
- **コンテキスト**: 直前2つの変換結果のみを送信
- **エラー時**: `:echo` で一時メッセージ表示、行はローマ字のまま残す

## 設計方針

- 複雑なロジック（キャッシュ、LLM 呼び出し）はすべてエンジン側に集約
- プラグインはキャッシュの存在を意識不要
- 将来的に VSCode 等への移植を考慮した構造
- 非同期安全：行番号 + ハッシュで追跡し、編集されたらキャンセル

## 仕様書

| ファイル | 内容 |
|---|---|
| `spec/LazyJP_01_全体像.md` | 目的・全体アーキテクチャ・設計決定 |
| `spec/LazyJP_02_エンジン仕様.md` | API 仕様・キャッシュ仕様・エラー処理 |
| `spec/LazyJP_03_プラグイン仕様.md` | Neovim プラグインの動作フロー・通信仕様 |
