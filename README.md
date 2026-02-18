# claude-code-kit

Claude Code を少しだけ楽しく使うためのセットアップキット。

CLAUDE.md / CLAUDE.local.md と周辺ツールの一式で、セッションをまたいで記憶が続く Claude Code 環境を構築します。

## 何ができるか

- **記憶の永続化**: 作業履歴・ユーザー情報が自動でファイルに残り、次のセッションに引き継がれる。「はじめまして」から始まらない継続した関係
- **タスク管理**: IDEAS → TODO → 実装ログ → 完了のライフサイクルで、セッションをまたぐ中長期タスクを管理
- **セッション引き継ぎ**: 「次回やること」をファイルに残して、次のセッションでスムーズに再開
- **プロジェクト間連携**: inbox を使って別プロジェクトの Claude に依頼を送信、自動処理して結果を受け取る非同期メッセージング
- **ステータスライン**: コンテキスト残量をリアルタイム表示
- **人格システム**: 12種類のプリセット（お嬢様、ギャル、執事、博士...）から選んでセットアップ。口調・性格・フレーバーを自由に組み合わせてカスタマイズもできる

## 外部依存

セットアップ前に以下のツールをインストールしてください。

| ツール | 用途 | インストール |
|--------|------|--------------|
| **jq** | JSON パース | `sudo apt install jq` / `brew install jq` |
| **ccexport** | セッション情報取得・ログエクスポート | `pipx install git+https://github.com/yosagi/ccexport.git` |
| **osc-tap** | OSC シーケンスキャプチャ（任意） | `pipx install git+https://github.com/yosagi/osc-tap.git` |

## ファイル構成

```
dist/
├── .claude/
│   ├── hooks/
│   │   └── session_end.sh      # [グローバル] セッション終了時hook
│   ├── skills/
│   │   ├── inbox/              # [グローバル] プロジェクト間連携（送受信・既読・完了）
│   │   ├── inbox-dispatch/     # [グローバル] プロジェクト間連携（自動処理起動）
│   │   ├── inbox-process/      # [グローバル] inbox 依頼の自動処理
│   │   ├── inbox-process-ephemeral/  # [グローバル] inbox 依頼の自動処理（軽量版）
│   │   ├── memory-compact/     # [グローバル] 記憶ファイルの圧縮・要約
│   │   └── work-logger/        # [グローバル] journals 記録
│   ├── statusline.sh           # [グローバル] Status Line（コンテキスト残量表示）
│   └── export_session          # [ローカル] opt-in フラグ（テンプレート）
├── reports/
│   ├── inbox/                  # [ローカル] プロジェクト間連携受信箱
│   └── next_session.md         # [ローカル] セッション引き継ぎ
├── scripts/
│   └── claude-code              # [グローバル] osc-tap 経由の起動ラッパー → ~/.local/bin/
├── CLAUDE.md                   # [ローカル] ワークフロー定義
├── CLAUDE.local.md             # [ローカル] 人格セットアップ用
├── install-skill.sh            # スキルインストーラー（個別追加用）
├── setup_global.sh             # グローバル設定の統合インストーラ
├── setup_claude_permissions.sh # (個別) 許可設定のみ追加
└── README.md                   # このファイル
```

- **グローバル**: `~/.claude/` に1回インストールすれば全プロジェクトで使える
  - Skills は `allowed-tools` にグローバルパスがハードコードされているため、グローバルインストール必須
- **ローカル**: 各プロジェクトにコピーする

## セットアップ手順

### 1. 新規 PC の初期セットアップ（1回だけ）

```bash
# グローバル設定を一括インストール
dist/setup_global.sh --install
```

これで以下がインストールされます：
- Skills (inbox, inbox-dispatch, inbox-process, inbox-process-ephemeral, memory-compact, work-logger)
- Sandbox 例外設定（スクリプトを含むスキルの excludedCommands）
- SessionEnd hook（セッション終了時のログエクスポート）
- Status Line（コンテキスト残量表示）
- 許可設定（記憶ファイルへのアクセス許可）
- claude-code ラッパー（osc-tap 経由の起動スクリプト、`~/.local/bin/claude-code`。osc-tap 未インストール時はスキップ）

セッションログは `~/Notes/journals/claude_sessions/` に出力されます。
変更したい場合は `~/.claude/hooks/session_end.sh` の `SESSION_LOG_DIR` を編集してください。

### 2. 新規プロジェクトのセットアップ

#### 2.1 必須ファイルのコピー

```bash
cd /path/to/your/project

# ワークフロー定義とセットアップ用ファイル
cp dist/CLAUDE.md .
cp dist/CLAUDE.local.md .
```

`reports/` ディレクトリ構造はワークフローに従って作業する中で必要に応じて自動的に作成されます。

<details>
<summary>完全に構築された reports/ の構造（参考）</summary>

```
reports/
├── ideas/                 # アイデア段階のメモ
│   ├── INDEX.md
│   ├── done/
│   └── rejected/
├── todos/                 # 中長期的なタスク
│   ├── INDEX.md
│   ├── done/
│   └── rejected/
├── inbox/                 # プロジェクト間連携の受信箱
│   ├── INDEX.md
│   ├── done/
│   └── draft/             # 送信前の下書き
├── memory/                # 共通記憶
│   ├── work_history.md    # 作業履歴
│   └── user_profile.md    # ユーザー情報
├── personas/              # 人格固有の記憶
│   └── [人格名].md        # 日記
├── tasks/                 # 実装ログ
│   └── YYYY-MM-DD_task_[topic].md
└── next_session.md        # セッション引き継ぎ
```

</details>

#### 2.2 人格セットアップ

Claude Code を起動すると、CLAUDE.local.md のセットアップ手順に従って人格設定が始まります。

```bash
claude
```

#### 2.3 セッションログ出力の有効化（任意）

セッションログを出力したい場合は opt-in フラグを作成：

```bash
mkdir -p .claude
touch .claude/export_session
```

### 個別スキルの追加インストール

スキルを個別にインストールする場合は `install-skill.sh` を使用できます：

```bash
dist/install-skill.sh dist/.claude/skills/inbox
```

これは以下を行います：
- スキルを `~/.claude/skills/` にコピー
- スクリプト（*.sh, *.py）があれば `settings.json` の `sandbox.excludedCommands` に自動追加

## 設定の確認

```bash
# グローバル設定の状態を確認
dist/setup_global.sh --status
```

出力例:
```
Claude Code グローバル設定の状態:

Skills:
  ✓ inbox
  ✓ inbox-dispatch
  ✓ inbox-process
  ✓ inbox-process-ephemeral
  ✓ memory-compact
  ✓ work-logger

Hooks:
  ✓ session_end.sh

Status Line:
  ✓ statusline.sh

settings.json:
  ✓ SessionEnd hook 設定あり
  ✓ statusLine 設定あり
  許可設定: 15 件

依存関係:
  ✓ jq: /usr/bin/jq
  ✓ ccexport: /home/user/.local/bin/ccexport

セッションログ: /home/user/Notes/journals/claude_sessions (28 ファイル)
```

## トラブルシューティング

### ccexport が見つからない

```bash
pipx install git+https://github.com/yosagi/ccexport.git
```

### jq が見つからない

```bash
# Ubuntu/Debian
sudo apt install jq

# macOS
brew install jq
```

### セッションログが出力されない

1. opt-in フラグがあるか確認: `ls -la .claude/export_session`
2. hook の状態を確認: `~/.claude/hooks/session_end.sh --status`
3. 出力先ディレクトリが存在するか確認: `ls ~/Notes/journals/claude_sessions/`

## 既存プロジェクトへの適用

既に CLAUDE.md があるプロジェクトに適用する場合：

1. **プロジェクト固有情報を分離**
   - 既存の CLAUDE.md からプロジェクト固有の情報（目標、方針、アーキテクチャ決定事項など）を抽出
   - `reports/project_context.md` に移動
   - dist/CLAUDE.md は汎用ワークフロー定義のみを含み、プロジェクト固有情報は `@reports/project_context.md` でインクルードする構成

2. **CLAUDE.md を置き換え**
   - dist/CLAUDE.md で上書き
   - 必要に応じて `@reports/project_context.md` のインクルードを確認

3. **人格設定は維持**
   - CLAUDE.local.md は各プロジェクト固有のため、上書きしない
   - 人格を変更したい場合はセットアップをやり直す
