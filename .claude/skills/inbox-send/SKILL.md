---
name: inbox-send
description: 他プロジェクトへ依頼を送信する
user_invocable: true
allowed-tools: Bash(~/.claude/skills/inbox-send/inbox-send.sh:*), Bash(~/.claude/skills/inbox-send/inbox-dispatch.sh:*), Bash(~/.claude/skills/inbox-send/find-project.sh:*)
---

# inbox-send スキル

他プロジェクトの inbox に依頼を送信する。必要に応じて受信側で自動処理も起動できる。

## 使い方

```
/inbox-send [送信先のヒント] [依頼内容の概要]
```

## 処理手順

### 1. プロジェクトルートに移動

```bash
cd /path/to/project/root
```

サブディレクトリにいると draft やファイルを間違った場所に作成してしまう。

### 2. 依頼内容をユーザーと相談

- 何をしてほしいか
- 期待する成果物

### 3. 送信先を特定

`~/.claude/skills/inbox-send/find-project.sh [キーワード]` で検索。キーワードなしで全一覧、ありでパス・プロジェクト名・人格名・概要で絞り込み。

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
draft ディレクトリがなければ `reports/inbox/draft/` を作成する。
日付がわからない場合は `date +%Y-%m-%d` で確認。

### 5. 依頼を送信

```bash
~/.claude/skills/inbox-send/inbox-send.sh [送信先] [draft ファイル] [送信元名] [日付]
```

出力から送信されたファイル名を取得する（例: `2026-02-05_from_claude_topic.md`）

### 6. 受信側で自動処理を起動（ユーザーの指示があれば）

ユーザーに自動処理を起動するか確認する。起動する場合は ephemeral かどうかも確認する。

```bash
~/.claude/skills/inbox-send/inbox-dispatch.sh [送信先プロジェクトルート] [送信されたファイル名] [--ephemeral]
```

**`--ephemeral` の判断基準**: コードベースに変更を加えるかどうかで判断する。
- **通常（デフォルト）**: バグ修正、機能追加、リファクタリングなどコード変更を伴う作業
- **`--ephemeral`**: 調査・問い合わせ、プログラムの実行・実験、ビルド・インストール作業など、コードを編集しない作業

### 7. 起動を報告

ユーザーに以下を報告:
- 依頼を送信したこと
- 受信側で処理を起動した場合はそのことと、ログファイルの場所
- 結果は inbox に届く予定であること

## 注意事項

- 依頼内容はユーザーと相談して決める
- 期待する成果物は具体的に書く（受け手が迷わないように）
- 受信側の処理はバックグラウンドで実行される（非同期）
- ログファイルで進捗を確認できる
