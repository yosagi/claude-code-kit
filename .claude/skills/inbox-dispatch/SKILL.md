---
name: inbox-dispatch
description: 依頼を送信し、受信側で自動処理を起動する
user_invocable: true
allowed-tools: Bash(~/.claude/skills/inbox/inbox.sh:*), Bash(~/.claude/skills/inbox-dispatch/inbox-dispatch.sh:*)
---

# inbox-dispatch スキル

依頼を送信した後、受信側プロジェクトで `claude -p` を使って自動処理を起動する。

## 使い方

```
/inbox-dispatch [送信先のヒント] [依頼内容の概要]
```

## 処理手順

### 1. プロジェクトルートに移動

```bash
cd /path/to/project/root
```

### 2. 依頼内容をユーザーと相談

- 何をしてほしいか
- 期待する成果物

### 3. 送信先を特定

**ヒントの種類:**
- パス: そのまま使用（例: `~/work/myproject`）
- プロジェクト名: `ccexport projects` から検索
- 人格名: 各プロジェクトの CLAUDE.local.md を確認

### 4. draft ファイルを作成

`reports/inbox/draft/to_[送信先ヒント]_[トピック].md`:

```markdown
送信先: [送信先プロジェクトルート]

# 依頼: [タイトル]

- **依頼元**: [現在のプロジェクト名]（[人格名]）
- **期待する成果物**: [何をしてほしいか]
- **報告先**: [現在のプロジェクトルート]

## 詳細

[依頼内容の詳細]
```

**注意**: 「送信先」「報告先」はプロジェクトルートを指定する。

### 5. 依頼を送信

```bash
~/.claude/skills/inbox/inbox.sh send [送信先] [draft ファイル] [送信元名] [日付]
```

出力から送信されたファイル名を取得する（例: `2026-02-05_from_claude_topic.md`）

### 6. 受信側で自動処理を起動

```bash
~/.claude/skills/inbox-dispatch/inbox-dispatch.sh [送信先プロジェクトルート] [送信されたファイル名] [--ephemeral]
```

**例:**
```bash
# 通常版（実装ログ・work_history 記録あり、デフォルト）
~/.claude/skills/inbox-dispatch/inbox-dispatch.sh ~/work/myproject 2026-02-05_from_claude_topic.md

# 軽量版（記録なし、簡単な依頼向け）
~/.claude/skills/inbox-dispatch/inbox-dispatch.sh ~/work/myproject 2026-02-05_from_claude_topic.md --ephemeral
```

**`--ephemeral` の判断基準**: コードベースに変更を加えるかどうかで判断する。
- **通常版（デフォルト）**: バグ修正、機能追加、リファクタリングなどコード変更を伴う作業
- **`--ephemeral`**: 調査・問い合わせ、プログラムの実行・実験、ビルド・インストール作業など、コードを編集しない作業

このスクリプトは:
- ログディレクトリを作成（なければ）
- `cd [送信先] && claude -p "/inbox-process ..."` をバックグラウンドで実行
- ログを `reports/inbox-logs/[タイムスタンプ]_[トピック].log` に出力

### 7. 起動を報告

ユーザーに以下を報告:
- 依頼を送信したこと
- 受信側で処理を起動したこと
- ログファイルの場所
- 結果は inbox に届く予定であること

## 注意事項

- 受信側の処理はバックグラウンドで実行される
- 結果は受信側から inbox に返信される
- 処理が完了するまで待つ必要はない（非同期）
- ログファイルで進捗を確認できる