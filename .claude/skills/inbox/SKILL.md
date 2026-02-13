---
name: inbox
description: プロジェクト間連携（依頼の送信・受信・完了処理）
user_invocable: true
allowed-tools: Bash(~/.claude/skills/inbox/inbox.sh:*)
---

# inbox スキル

プロジェクト間で依頼を送受信する。送信・既読化・完了処理を一つのスキルで扱う。

## 使い方

```
/inbox send [送信先のヒント] [依頼内容の概要]
/inbox read [ファイル名]
/inbox done [ファイル名]
```

## 共通の最初の手順

**すべてのコマンドで、最初にプロジェクトルートに移動すること。**

```bash
cd /path/to/project/root
```

サブディレクトリにいると draft やファイルを間違った場所に作成してしまう。

## コマンド

### send - 依頼を送信

他プロジェクトの inbox に依頼を送信する。

**手順:**
1. プロジェクトルートに移動（上記参照）
2. ユーザーと依頼内容を相談
3. 送信先を特定（下記「送信先の探し方」参照）
4. draft ファイルを作成: `reports/inbox/draft/to_[送信先ヒント]_[トピック].md`
5. inbox.sh で配送

**draft ファイルのフォーマット:**
```markdown
送信先: [送信先プロジェクトのパス]

# 依頼: [タイトル]

- **依頼元**: [現在のプロジェクト名]（[人格名]）
- **期待する成果物**: [何をしてほしいか]
- **報告先**: [現在のプロジェクトルート]

## 詳細

[依頼内容の詳細]
```

**注意**: 「送信先」「報告先」はプロジェクトルート（例: `~/work/myproject`）を指定する。
`/reports/inbox` は自動で追加されるため、含めなくてよい（含めても自動で正規化される）。

**配送コマンド:**
```bash
~/.claude/skills/inbox/inbox.sh send \
  [送信先プロジェクトパス] \
  reports/inbox/draft/to_xxx_topic.md \
  [現在のプロジェクト名] \
  [日付 YYYY-MM-DD]
```

### read - 受信した依頼を読む

INDEX.md の [NEW] マーカーを削除し、内容を表示する。

```bash
~/.claude/skills/inbox/inbox.sh read [ファイル名]
```

### done - 依頼を完了

処理済みの依頼を done/ に移動し、INDEX.md から削除する。

```bash
~/.claude/skills/inbox/inbox.sh done [ファイル名]
```

## 送信先の探し方

1. **プロジェクト一覧を取得**: `ccexport projects`
2. **スコープを確認**: 候補プロジェクトの `reports/project_context.md` を読む
3. **人格名で探す場合**: 各プロジェクトの `CLAUDE.local.md` を確認

**ヒントの種類:**
- パス: そのまま使用（例: `~/work/myproject`）
- プロジェクト名: ccexport projects から検索（例: `myproject`）
- 人格名: 各プロジェクトの CLAUDE.local.md を確認

## INDEX.md の形式

```markdown
# INBOX インデックス

外部プロジェクトからの依頼一覧。詳細は各ファイルを参照。

- [NEW] 2026-01-25_from_claude_request.md
- 2026-01-24_from_lab_notification.md
```

- `[NEW]` マーカー: 未読
- マーカーなし: 既読（read 実行済み）

## 注意

- 依頼内容はユーザーと相談して決める
- 期待する成果物は具体的に書く（受け手が迷わないように）
- draft ディレクトリがなければ `reports/inbox/draft/` を作成する
- 日付がわからない場合は `date +%Y-%m-%d` で確認
