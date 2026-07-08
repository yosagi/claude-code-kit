---
name: global-kb
description: プロジェクト横断で再利用される知見をグローバル KB（claude-registry）に記録・更新する。ユーザーが「グローバル KB に記録して」と指示したとき、または知見の記録先がプロジェクト KB かグローバル KB か判断が必要なときに使用する。
user_invocable: true
---

# グローバル KB への記録

## 仕組みの概要

グローバル KB は複数プロジェクト・複数 PC で共有される横断知見の置き場。

- **置き場**: `~/Notes/claude-registry/<hostname>/kb/`。registry は Syncthing で全 PC に同期され、読み取りは全ホストの kb/ を横断するため、どのホストに書いた KB もすべての PC・プロジェクトから見える
- **書き込み contract**: ホスト間同期のコンフリクトを避けるため、registry には自ホスト名以下のディレクトリしか書き込まない。ホスト非依存の共通置き場（`claude-registry/kb/`）は置かない（2026-07-07 に廃止）
- **注入の流れ**: claude-code wrapper が起動時に `~/.claude/scripts/build_startup_context.py` を実行し、全ホストの KB からプロジェクト・ホストの関心タグ（kb_interests）にマッチしたものを選んで `tmp/global_kb_context.md` に書き出す。これが CLAUDE.md の @ インクルードでコンテキストに入る
- **重複排除**: 同名ファイルが複数ホストの kb/ にある場合、mtime が新しい方が採用される

## 記録対象の判断

- **グローバル KB**: プロジェクト横断で再利用される知見。ツール・ライブラリの罠、実行環境の特性（sandbox 等）、全プロジェクト共通ルールなど
- **プロジェクト KB（`reports/kb/`）**: そのプロジェクト固有の調査結果。従来通りの運用
- 判断基準は「別のプロジェクトでも同じ問題に出会うか」。迷った場合はユーザーに確認する

## ファイル形式

ファイル名は `topic.md`（snake_case）。プロジェクト KB と異なり日付プレフィックスは付けない。

```markdown
---
tags: [tag1, tag2]
inject: full
summary: 1行の要約（index 注入時はこれだけが表示される）
---

# タイトル

本文...
```

- **tags**: 注入先の選択に使われる。下記「既存タグ一覧」から再利用するタグを選ぶのを基本とし、新設は既存タグでは意味がずれる場合に限る。新設した場合は後述の kb_interests 設定が必要
- **inject**:
  - `full` — 本文全体が起動時コンテキストに注入される。常に意識すべき短いルール・罠に使う。毎セッションのコンテキストに全文が乗るため、目安30行以内に収める
  - `index` — summary とファイルパスのみ注入され、AI が必要時に Read する。長い reference・パターン集に使う
- **本文**: `# タイトル` + 概要 + 詳細。`full` の場合は前置きなしで要点から書く

## 既存タグ一覧

現在のグローバル KB で使われているタグとホスト単位の kb_interests（スキルロード時に取得）:

!`python3 ~/.claude/skills/global-kb/scripts/list_tags.py`

## 手順

### 1. 内容の整理と提案

記録する知見・ファイル名・tags・inject・summary を決め、ユーザーに提示して確認を取る。
tags は上記「既存タグ一覧」を参照して選ぶ。

### 2. 書き込み

書き込みは常に自ホストのディレクトリに対して行う（書き込み contract）:

```
~/Notes/claude-registry/<hostname>/kb/<topic>.md
```

hostname は `hostname` コマンドで確認する。

- **新規作成**: 自ホストの kb/ に Write する
- **自ホストの kb/ にあるファイルの更新**: 直接 Edit する
- **他ホストの kb/ にあるファイルの更新**: 他ホストのディレクトリは編集しない。自ホストの kb/ に同名ファイルとして全文（更新後の内容）を Write する。読み取り側の mtime 重複排除により新しい方が採用される

### 3. 注入先の設定（kb_interests）

KB は、タグが「プロジェクトの kb_interests ∪ ホストの kb_interests」と交差するプロジェクトにのみ注入される。新しいタグを使った場合、どこに注入されるべきかをユーザーに確認し、設定する:

- **プロジェクト単位**: 対象プロジェクトの `reports/project_context.md` に記載する
  ```
  kb_interests: [tag1, tag2]
  ```
  （既存の行があればタグを追記する）
- **ホスト単位**（そのホストの全プロジェクトに適用）: `~/Notes/claude-registry/<hostname>/kb_interests` に1行1タグで追記する（`#` で始まる行はコメント）

自プロジェクトの project_context.md は直接編集してよい。他プロジェクトの分は直接編集せず、`/inbox-send` で依頼するかユーザーに設定内容を伝える。

### 4. 検証

現在のプロジェクトが対象タグに関心を持つ場合:

```bash
claude-code --show-context
```

別プロジェクトが対象の場合はパスを指定して直接実行する:

```bash
python3 ~/.claude/scripts/build_startup_context.py <対象プロジェクトのパス>
```

書いた KB が期待どおり注入（full なら全文、index なら summary + パス）されることを確認し、結果をユーザーに報告する。
