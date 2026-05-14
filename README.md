# claude-code-kit

Claude Code を少しだけ楽しく使うためのセットアップキット。

CLAUDE.md / CLAUDE.local.md と周辺ツールの一式で、セッションをまたいで記憶が続く Claude Code 環境を構築します。

## 何ができるか

- **記憶の永続化**: 作業履歴・ユーザー情報が自動でファイルに残り、次のセッションに引き継がれる。「はじめまして」から始まらない継続した関係
- **タスク管理**: IDEAS → TODO → 実装ログ → 完了のライフサイクルで、セッションをまたぐ中長期タスクを管理
- **ナレッジベース**: 調査結果を KB に蓄積し、プロジェクトの知見を永続化
- **セッション引き継ぎ**: 進行中の作業状態をファイルに残して、次のセッションでスムーズに再開
- **プロジェクト間連携**: inbox を使って別プロジェクトの Claude に依頼を送信、自動処理して結果を受け取る非同期メッセージング。マルチPC対応
- **定期洞察（insight）**: プロジェクトの状態を自動分析し、TODO/IDEAS の整理提案・知見抽出・横断的な気づきをレポート
- **自動バックアップ**: セッション終了時に記憶・タスク管理・設定ファイルを registry に自動バックアップ。次のセッション開始時に整合性チェック
- **ステータスライン**: コンテキスト使用率、rate limits、IDEAS/TODO/inbox 件数をリアルタイム表示
- **人格システム**: 多数の人格サンプルをもとに、口調・性格・フレーバーを自由に組み合わせて人格を提案。既存プロジェクトで使っている人格の分布を踏まえて、被らない方向も自動で提案
- **マルチPC自動同期**: claude-code ラッパーが起動時に設定の更新を検知し、自動インストール。CLAUDE.md / CLAUDE.local.md も自動配置・更新確認

## 外部依存

| ツール | 用途 | インストール |
|--------|------|--------------|
| **jq** | JSON パース | `sudo apt install jq` / `brew install jq` |
| **uv** | Python ツール管理 | `curl -LsSf https://astral.sh/uv/install.sh \| sh` |
| **ccexport** | セッション情報取得・ログエクスポート | `uv tool install git+https://github.com/yosagi/ccexport.git` |
| **osc-tap** | OSC シーケンスキャプチャ（任意） | `uv tool install git+https://github.com/yosagi/osc-tap.git` |

`bootstrap.sh` を使えばこれらの導入からグローバル設定まで一括で行えます。

## セットアップ

### 1. 初期セットアップ（PCごとに1回）

```bash
# 依存ツール導入 + グローバル設定を一括インストール
./bootstrap.sh
```

これで以下がインストールされます：
- 依存ツール（jq, ccexport, osc-tap）
- Skills（inbox, inbox-send, persona-setup, insight, stocktake, note-logger 等）
- Hooks（SessionStart: registry 登録、SessionEnd: ログエクスポート・バックアップ・記憶ドラフト処理）
- Status Line（コンテキスト使用率・rate limits 表示）
- Sandbox 例外設定、許可設定
- claude-code ラッパー（osc-tap 経由の起動スクリプト、auto-install 機能付き）
- グローバルルール（`~/.claude/CLAUDE.md` + `registry/global_rules.md`、初回のみ）

更新時も `bootstrap.sh` を再実行すれば最新化されます（`--force` でツールも再インストール）。
既存の `~/.claude/settings.json` は自動的に `settings.json.bak` にバックアップされます。

複数PCで使う場合は、`~/Notes/claude-registry/` を Syncthing 等でPC間同期した上で、`~/Notes/claude-registry/dist/` に配置すれば、他のPCでは `claude-code` 起動時に自動インストールされます。

### 2. プロジェクトのセットアップ

`claude-code` ラッパー経由で起動すると、CLAUDE.md / CLAUDE.local.md が自動配置されます。

```bash
cd /path/to/your/project

# .gitignore に追加（推奨）
echo -e "reports/\nwork_in_progress.md\nCLAUDE.local.md" >> .gitignore

# Claude Code を起動（CLAUDE.md / CLAUDE.local.md が自動配置される）
claude-code
```

ラッパーを使わない場合は手動でコピーしてください：

```bash
cp /path/to/dist/CLAUDE.md .
cp /path/to/dist/CLAUDE.local.md .
cp /path/to/dist/work_in_progress.md .
```

`reports/`（記憶・タスク管理等）、`work_in_progress.md`（作業状態）、`CLAUDE.local.md`（人格設定の `@` インクルード）は個人の作業データなので、git 管理外にすることを推奨します。`CLAUDE.md`（ワークフロー定義）はチームで共有する場合にコミットしても構いません。

初回起動時に `/persona-setup` スキルが人格セットアップを案内します。
人格を定義するか素のClaudeで進めるかを選択し、定義する場合は既存人格の分布を踏まえた提案を受けられます。
完了すると `reports/` 以下にプロジェクト構造が作成されます。

CLAUDE.md の自動同期を無効にしたいプロジェクトでは、プロジェクトルートに `.no-claude-md-sync` を置いてください。

### 3. 定期洞察の設定（任意）

insight を定期実行して、プロジェクトの状態を自動分析できます。

```bash
# 毎日実行（systemd user timer）
scripts/insight-schedule.sh enable ~/work/myproject --schedule daily

# 毎週月曜（デフォルト）
scripts/insight-schedule.sh enable ~/work/myproject

# 一覧表示
scripts/insight-schedule.sh list

# 手動実行
scripts/insight-schedule.sh run ~/work/myproject

# ログ確認
scripts/insight-schedule.sh logs ~/work/myproject

# 無効化
scripts/insight-schedule.sh disable ~/work/myproject
```

insight はプロジェクトの棚卸し（TODO/IDEAS の整理提案、実装ログの健全性チェック）、記憶ファイルの圧縮、会話ログの横断分析を行い、レポートを生成します。結果は inbox に通知され、次のセッションで `/insight-review` で処理できます。

## 設計方針

### ワークフローとデータの分離

ワークフローの定義（CLAUDE.md, CLAUDE.local.md）とユーザー/プロジェクト固有のデータは分離して管理します。

| 種類 | ファイル | 内容 |
|------|----------|------|
| ワークフロー | `CLAUDE.md` | タスク管理、実装プロセス、記憶システム等の共通ルール |
| ワークフロー | `CLAUDE.local.md` | 記憶ファイルの `@` インクルード（全プロジェクト同一） |
| データ | `reports/project_context.md` | プロジェクトの目標・方針・規約 |
| データ | `reports/personas/config.md` | 人格設定（口調・性格） |
| データ | `reports/memory/` | 作業履歴・ユーザー情報 |
| データ | `global_rules.md` | 全プロジェクト共通のルール |

ワークフロー側は claude-code-kit の更新で上書きでき、データ側はプロジェクトやユーザーごとに独立して管理されます。

`global_rules.md` は全プロジェクト共通のルールを置くファイルで、`~/.claude/CLAUDE.md` から `@` インクルードされます。実体は `~/Notes/claude-registry/` に配置されます。`~/Notes/` を Syncthing 等でPC間同期していれば、ルールも自動的に共有されます。setup_global.sh は初回のみ空テンプレートを配置し、既存ファイルは上書きしません。

### ハードコードされたディレクトリ

以下のディレクトリパスがスクリプト内にハードコードされています。

| パス | 用途 |
|------|------|
| `~/Notes/claude-registry/` | セッション情報、バックアップ、ドラフト、グローバルルール。Syncthing 等でPC間同期する想定 |
| `~/Notes/journals/claude_sessions/` | 会話ログの出力先（opt-in） |
| `<project>/reports/` | 記憶、タスク管理、inbox、insight 等のプロジェクトローカルデータ |
| `~/.claude/osc-logs/` | osc-tap によるターミナルタイトルのキャプチャログ |

## ファイル構成

```
dist/
├── global.claude/
│   ├── hooks/
│   │   ├── session_start.sh          # registry 登録・バックアップ整合性チェック
│   │   ├── session_end.sh            # ログエクスポート・ダイジェスト出力・バックアップ
│   │   ├── process_journal_drafts.sh # ドラフト→journals 追記
│   │   ├── process_memory_drafts.sh  # 記憶ドラフト→work_history/diary 追記
│   │   ├── append_memory_entry.py    # 記憶ファイルへの追記処理
│   │   └── backup_project_state.sh   # reports/ バックアップ（session_end から起動）
│   ├── skills/
│   │   ├── inbox/                    # inbox 受信・既読・完了
│   │   ├── inbox-send/              # inbox 送信・検索・自動処理起動
│   │   ├── inbox-process/           # inbox 自動処理
│   │   ├── inbox-process-ephemeral/ # inbox 自動処理（軽量版）
│   │   ├── insight/                 # 定期洞察レポート生成
│   │   ├── insight-review/          # insight 提案の対話的処理
│   │   ├── stocktake/               # IDEAS/TODO/KB の棚卸し
│   │   ├── persona-setup/           # 人格セットアップ（init-project.sh、人格サンプル同梱）
│   │   ├── memory-compact/          # 記憶ファイルの圧縮・要約
│   │   ├── note-logger/             # 経緯・背景の journals 記録
│   │   └── work-logger/             # 作業ログの journals 記録
│   ├── statusline.sh                # ステータスライン
│   ├── global_rules.md              # グローバルルール テンプレート
│   └── export_session/              # セッションログ opt-in フラグ（テンプレート）
├── scripts/
│   ├── claude-code                  # 起動ラッパー（osc-tap、auto-install、CLAUDE.md 同期）
│   └── insight-schedule.sh          # insight 定期実行の管理（systemd user timer）
├── CLAUDE.md                        # [プロジェクト] ワークフロー定義
├── CLAUDE.local.md                  # [プロジェクト] 人格セットアップ用（全プロジェクト同一）
├── work_in_progress.md              # [プロジェクト] 進行中の作業状態
├── bootstrap.sh                     # 初期セットアップ（依存ツール + グローバル設定）
├── setup_global.sh                  # グローバル設定のインストーラ
├── install-skill.sh                 # スキル個別インストーラ
├── init-project.sh                  # プロジェクト構造の初期化（べき等）
└── setup_claude_permissions.sh      # 許可設定の個別追加
```

- **global.claude/**: `~/.claude/` にグローバルインストールされ、全プロジェクトで共有
- **プロジェクトファイル**: 各プロジェクトにコピーして使う

## 設定の確認

```bash
./setup_global.sh --status
```

## セッションログ

セッション終了時に以下が自動出力されます：

- **セッションダイジェスト**: `~/Notes/claude-registry/` にJSON形式（常に出力）
- **会話ログ**: `~/Notes/journals/claude_sessions/` にorg形式（opt-in）

会話ログの出力を有効にするには：

```bash
mkdir -p .claude
touch .claude/export_session
```

出力先を変更する場合は `~/.claude/hooks/session_end.sh` の `SESSION_LOG_DIR` を編集してください。

## 既存プロジェクトへの適用

1. **プロジェクト固有情報を分離**: 既存の CLAUDE.md からプロジェクト固有情報を `reports/project_context.md` に抽出
2. **CLAUDE.md を置き換え**: dist の CLAUDE.md で上書き（`@reports/project_context.md` でインクルードされる）
3. **CLAUDE.local.md をコピー**: dist の CLAUDE.local.md で上書き
4. **セッション起動**: `/persona-setup` で人格を設定
