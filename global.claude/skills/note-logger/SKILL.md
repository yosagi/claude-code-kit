---
name: note-logger
description: 共同作業の経緯・背景・試行錯誤を journal の「* Claude 雑記」セクションに三人称の地の文で記録する。ユーザーが明示的に指示したときのみ実行する。
user_invocable: true
allowed-tools: Bash(~/.claude/skills/note-logger/submit_draft.sh:*)
---

# 雑記記録 (note-logger)

作業の節目で「何が起こり・何を試し・何がわかったか」を journal の `* Claude 雑記` セクションに記録するスキル。work-logger（やった行動の事後記録）とは独立したスキルで、経緯・背景・試行錯誤・考察を残すために使う。

## トリガー

**ユーザーが明示的に指示したときのみ**実行する。セッション終了や作業完了を検知して自動発動はしない。

想定される指示例:
- 「note-logger で記録して」「雑記書いて」
- 「今の経緯残しておいて」
- `/note-logger`

## 本文のスタイル

- **三人称の地の文**で「何が起こり・何を試し・何がわかったか」を積む
- 誰がどう発言したかの会話引用は使わない（ユーザーのプロンプトをそのまま引用しない）
- 背景・動機 → 試行 → 結果 → 現状や次の一手、の流れを目安にする
- 書くべき項目は緩く、該当するものだけ書けばよい

良い例のイメージ:

> sandbox 配下の Bash ツールが `Exit 126` で全滅する症状が発生。Team Premium 切替とのタイミング一致から managed settings の atomic replace を疑ったが、policy-limits.json の中身が通常利用と無関係と判明し棄却。`ps` 実測で bwrap が一度も spawn されていないことを確認し、claude-code 側で合成された偽のエラーメッセージと推定。2.1.116 バイナリ直叩きで再現しないことを確認し、2.1.117 の regression と確定。

避けるべき記述:
- 「智章さんが『〜では？』と提案された」のような会話ログ的引用
- 主観・感情の羅列（それは diary に）

## 手順

### 1. プロジェクト名とタイトルを決める

- **project**: 本プロジェクトの journals 記録用名（`reports/project_context.md` の「journals 記録用」欄、通常はプロジェクトルートのディレクトリ名）
- **title**: 本文内容を短く要約した見出し（例: 「sandbox regression 調査」「note-logger 設計議論」）

### 2. 本文ドラフトを書き出す

Write ツールで本文ドラフトを作成する。**見出し行 `** ...` は書かない**（submit スクリプトが自動付与する）。

**ドラフトファイルのパス**: `reports/memory/note-logger-${CLAUDE_SESSION_ID}_draft.org`

本文は地の文で、段落単位で構成する。

### 3. **レビュー待ち**（重要）

ドラフトを書き出したら、本文を回答内にも**そのまま表示**し、ユーザーのレビューを待つ。

**このステップでは submit しない**。ユーザーから以下のような反応が来るまで停止する:
- 承認（「OK」「これで」「submit して」など）
- 修正指示（「もっとここ詳しく」「これ削って」「この段落を〜に書き換えて」など）

修正指示が来た場合は、ドラフトファイルを Edit または Write で更新し、更新版を再び回答内に表示してレビューを待つ。修正の往復は何度でも行ってよい。

### 4. Submit

ユーザーの承認が得られたタイミングで以下を実行:

```bash
~/.claude/skills/note-logger/submit_draft.sh <project> <title> <Step 2 で Write に渡した絶対パス>
```

submit_draft.sh が `** HH:MM [project@host] title` の見出しを本文に付与し、drafts ディレクトリに完成形を配置する。本文ファイルは削除される。journals への追記は後続の dispatcher（process_journal_drafts.sh）が自動で行う。

## 同一セッションでの複数トピック

1 セッション中に複数回呼ばれてよい。トピックごとに別サブセクションとして記録される（HH:MM が違うので見出しも重複しない）。

## トピックの粒度

- 同一トピックを後日続ける場合は、書いた日の journal に新規サブセクションとして追記する（時系列で辿れば繋がる）
- 1 エントリは 1 トピックに絞る。複数トピックを 1 エントリに詰め込まない

## org 記法への注意

ドラフト本文は org ファイル（journal）に貼り付けられるため、markdown ではなく org 記法で書く：

- 表の separator 行は `|---+---+---|`（markdown の `|---|---|` ではない）
- inline code は `=code=` または `~code~`（markdown の `` `code` `` ではない）
- 強調は `*bold*` / `/italic/` / `+strike+`
- 箇条書きは `- ` または `+ `
- リンクは `[[target][label]]`
