---
name: work-logger
description: このプロジェクトの作業の進捗記録をユーザが管理するjournalファイルに追記する。セッション終了が示されたとき、作業完了報告時、work_history.mdを更新する時に使用する。
allowed-tools: Bash(~/.claude/skills/work-logger/get_session_info.sh:*), Bash(~/.claude/skills/work-logger/get_journal_date.sh), Bash(~/.claude/skills/work-logger/submit_draft.sh:*), Bash(~/.claude/hooks/session_end.sh:*)
---

# 作業ログ記録 (work-logger)

## セッション情報（動的取得）

- セッション ID: `${CLAUDE_SESSION_ID}`
- プロジェクト名: !`~/.claude/skills/work-logger/get_session_info.sh --project ${CLAUDE_SESSION_ID}`
- 会話ログ出力: !`~/.claude/skills/work-logger/get_session_info.sh --opt-in ${CLAUDE_SESSION_ID}`

## トリガー

以下のタイミングで実行する：
- ユーザーが「おやすみ」「また明日」「終わり」などセッション終了を示唆したとき
- 実装完了を報告したとき
- work_history.md を更新したとき
- ユーザーが明示的に作業記録を依頼したとき

## 手順

### 1. 日付の決定

```bash
~/.claude/skills/work-logger/get_journal_date.sh
```

このスクリプトが返す日付を使用する。

### 2. 会話ログ連携（opt-in 時のみ）

**会話ログ出力が「有効」の場合のみ**、以下を実行：

```bash
~/.claude/hooks/session_end.sh --prepare ${CLAUDE_SESSION_ID}
```

このコマンドで以下が行われる：
- ファイル名を生成（`{プロジェクト名}_{日付}_{セッションID先頭8文字}.org`）
- 一時ファイル（`.claude/work-logger_${SESSION_ID}.txt`）に書き込み

SessionEnd hook がこの一時ファイルを読み取り、同じパスにエクスポートする。

**会話ログ出力が「無効」の場合**、このステップはスキップする。

### 3. エントリのドラフト作成

Write ツールでドラフトファイルを作成する。

**ドラフトファイルのパス**: `reports/memory/work-logger-${CLAUDE_SESSION_ID}_draft.org`

**記載内容**:
- その日（セッション）で行った作業の簡潔なまとめ
- 各項目は `- ` で始める箇条書き
- 技術的な詳細より「何をしたか」を重視
- ユーザーから設計意図や方針が示されていた場合は簡潔に記録

**会話ログ出力が「有効」の場合**、最後の作業項目の末尾に会話ログへのリンクを追加：
```
- 作業内容の説明 [[file:claude_sessions/{プロジェクト名}_YYYY-MM-DD_{セッションID先頭8文字}.org][会話ログ]]
```

**会話ログ出力が「無効」の場合**、リンクは追加しない。

### 3b. セッションダイジェストの書き出し

セッションで行った作業を **1行（80文字程度）** で要約し、以下のファイルに Write ツールで書き出す。

**ダイジェストファイルのパス**: `reports/memory/work-logger-${CLAUDE_SESSION_ID}_digest.txt`

**記載内容**:
- ドラフト（Step 3）の内容を1行に凝縮した要約
- 改行なし、末尾改行のみ
- 例: `insight スキルの展開作業と cron 自動化`

SessionEnd hook がこのファイルを読み取り、registry に JSON を書き出す。

### 4. ドラフトの提出

以下のコマンドでドラフトを提出する：

```bash
~/.claude/skills/work-logger/submit_draft.sh {日付} {プロジェクト名} {Step 3 で Write に渡した絶対パス}
```

ドラフトの提出後、journals への追記は後続スクリプトが自動で行う。

## ドラフトの記載例

ドラフトには箇条書きの本文のみを記載する。セクションヘッダ（`*` や `**`）は書かない。

### 会話ログリンクあり（opt-in 時）

```org
- journals への作業ログ自動追記機能を設計
  - 後で収集してローカルLLMでまとめるより、作業した本人がその場で書くほうが正確という判断
- Skills として work-logger を実装 [[file:claude_sessions/claude_2026-01-03_a1b2c3d4.org][会話ログ]]
```

### 会話ログリンクなし

```org
- inbox 機能のテスト
- send-inbox スキルの動作確認
```