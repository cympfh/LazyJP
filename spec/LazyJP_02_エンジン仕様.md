# LazyJP 仕様書 - 02. エンジン側の仕様

**作成日**: 2026-06-09  
**バージョン**: v0.4（分離版）

---

## 2. エンジン側の仕様

### 2.1 役割
- ローマ字（および混在言語）を自然な文章に変換する
- キャッシュによる高速化とコスト削減
- 無期限ディスク永続化

### 2.2 技術スタック
- Python + FastAPI
- LiteLLM（モデル/プロバイダの抽象化）
- SQLite（キャッシュ永続化）

### 2.3 主要エンドポイント（提案）

#### POST /convert
リクエストでローマ字を受け取り、変換結果を返す。

**リクエスト例**
```json
{
  "input_text": "knnchw、nh",
  "style": "casual",
  "languages": ["ja", "zh"]
}
```

**レスポンス例**
```json
{
  "result_text": "こんにちは、你好",
  "cached": false
}
```

### 2.4 キャッシュ仕様

#### キャッシュキー
以下の3要素で一意に識別：
- ローマ字入力テキスト（正規化後）
- 文体（システムプロンプトのハッシュ）
- 使用言語宣言（日本語 / 英語 / 中国語 の組み合わせ）

#### 保存方式
- **データベース**: SQLite（`cache.db`）
- **有効期限**: なし（無期限永続化）
- **最大エントリ数**: 制限なし

#### テーブル構造（提案）
```sql
CREATE TABLE IF NOT EXISTS conversion_cache (
    cache_key TEXT PRIMARY KEY,
    input_text TEXT NOT NULL,
    style_hash TEXT NOT NULL,
    language_decl TEXT NOT NULL,
    result_text TEXT NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    last_used_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
```

#### 動作
- 同じcache_keyの入力が来たら、即座に結果を返す（LLMを呼ばない）
- ヒット時は `last_used_at` を更新
- コンテキストはキャッシュキーに含めない

### 2.5 エラー処理
- LLM呼び出しに失敗した場合、適切なエラーレスポンスを返す
- 呼び出し元（プラグイン）でエラーメッセージを表示する想定