---
name: inbox
description: 受信した依頼の確認・完了処理
user_invocable: true
allowed-tools: Bash(~/.claude/skills/inbox/inbox-read.sh:*)
---

# inbox スキル

受信した依頼を確認（既読化）し、処理完了後にアーカイブする。

## 使い方

```
/inbox read [ファイル名]
/inbox done [ファイル名]
```

## スクリプトの呼び出し方

`inbox-read.sh` には **`-C` でプロジェクトルートを渡す**（システムプロンプトの「Primary working directory」の値）。
スクリプトが自分でそのディレクトリへ移動するので、`cd` は不要。

`inbox-read.sh` は単独の Bash 呼び出しで実行する。`cd`・パイプ・リダイレクト・`;`・`&&` と連結すると
コマンド全体が excludedCommands に合致せず sandbox 内で走り、`reports/inbox/` の書き込みで失敗する。

## コマンド

### read - 受信した依頼を読む

INDEX.md の [NEW] マーカーを削除し、内容を表示する。

```bash
~/.claude/skills/inbox/inbox-read.sh -C [プロジェクトルート] read [ファイル名]
```

### done - 依頼を完了

処理済みの依頼を done/ に移動し、INDEX.md から削除する。

```bash
~/.claude/skills/inbox/inbox-read.sh -C [プロジェクトルート] done [ファイル名]
```

## INDEX.md の形式

```markdown
# INBOX インデックス

外部プロジェクトからの依頼一覧。詳細は各ファイルを参照。

- [NEW] 2026-01-25_from_claude_request.md
- 2026-01-24_from_lab_notification.md
```

- `[NEW]` マーカー: 未読
- マーカーなし: 既読（read 実行済み）
