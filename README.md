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
- **ステータスライン**: コンテキスト使用率、rate limits、IDEAS/TODO/inbox 件数をリアルタイム表示
- **人格システム**: 13種類のプリセット（お嬢様、ギャル、執事、博士...）から選んでセットアップ。口調・性格・フレーバーを自由に組み合わせてカスタマイズもできる

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
- Skills（inbox, inbox-send, persona-setup, insight, stocktake 等10個）
- Hooks（SessionStart: registry 登録、SessionEnd: ログエクスポート）
- Status Line（コンテキスト使用率・rate limits 表示）
- Sandbox 例外設定、許可設定
- claude-code ラッパー（osc-tap 経由の起動スクリプト）

更新時も `bootstrap.sh` を再実行すれば最新化されます（`--force` でツールも再インストール）。
既存の `~/.claude/settings.json` は自動的に `settings.json.bak` にバックアップされます。

### 2. プロジェクトのセットアップ

```bash
cd /path/to/your/project

# ワークフロー定義をコピー
cp /path/to/dist/CLAUDE.md .
cp /path/to/dist/CLAUDE.local.md .

# Claude Code を起動
claude
```

初回起動時に `/persona-setup` スキルが人格セットアップを案内します。
13種類のプリセットから選ぶか、「おまかせ」で自動提案。
完了すると `reports/` 以下にプロジェクト構造が作成されます。

### 3. 定期洞察の設定（任意）

insight を定期実行して、プロジェクトの状態を自動分析できます。

```bash
# 毎日実行（systemd user timer）
scripts/insight-schedule.sh enable ~/work/myproject --schedule daily

# 毎週日曜（デフォルト）
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

## ファイル構成

```
dist/
├── .claude/
│   ├── hooks/
│   │   ├── session_start.sh    # [グローバル] registry 登録
│   │   └── session_end.sh      # [グローバル] ログエクスポート・ダイジェスト出力
│   ├── skills/
│   │   ├── inbox/              # [グローバル] inbox 受信・既読・完了
│   │   ├── inbox-send/         # [グローバル] inbox 送信・検索・自動処理起動
│   │   ├── inbox-process/      # [グローバル] inbox 自動処理
│   │   ├── inbox-process-ephemeral/  # [グローバル] inbox 自動処理（軽量版）
│   │   ├── insight/            # [グローバル] 定期洞察レポート生成
│   │   ├── insight-review/     # [グローバル] insight 提案の対話的処理
│   │   ├── stocktake/          # [グローバル] IDEAS/TODO/KB の棚卸し
│   │   ├── persona-setup/      # [グローバル] 人格セットアップ（init-project.sh 同梱）
│   │   ├── memory-compact/     # [グローバル] 記憶ファイルの圧縮・要約
│   │   └── work-logger/        # [グローバル] journals 記録
│   ├── statusline.sh           # [グローバル] ステータスライン
│   └── export_session          # [ローカル] セッションログ opt-in フラグ（テンプレート）
├── scripts/
│   ├── claude-code             # [グローバル] osc-tap 経由の起動ラッパー
│   └── insight-schedule.sh     # insight 定期実行の管理（systemd user timer）
├── CLAUDE.md                   # [ローカル] ワークフロー定義
├── CLAUDE.local.md             # [ローカル] 人格セットアップ用（全プロジェクト同一）
├── work_in_progress.md         # [ローカル] 進行中の作業状態
├── bootstrap.sh                # 初期セットアップ（依存ツール + グローバル設定）
├── setup_global.sh             # グローバル設定のインストーラ
├── install-skill.sh            # スキル個別インストーラ
├── init-project.sh             # プロジェクト構造の初期化（べき等）
└── setup_claude_permissions.sh # 許可設定の個別追加
```

- **グローバル**: `~/.claude/` に1回インストールすれば全プロジェクトで使える
- **ローカル**: 各プロジェクトにコピーする

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

## トラブルシューティング

### セットアップ後にスキルが認識されない

スキルは `~/.claude/skills/` にグローバルインストールされます。`allowed-tools` にグローバルパスがハードコードされているため、グローバルインストールが必須です。

```bash
./setup_global.sh --status   # インストール状態を確認
./setup_global.sh --install  # 再インストール
```

### セッションログが出力されない

1. opt-in フラグの確認: `ls -la .claude/export_session`
2. hook の状態確認: `~/.claude/hooks/session_end.sh --status`
3. 出力先の確認: `ls ~/Notes/journals/claude_sessions/`

### insight が実行されない

```bash
scripts/insight-schedule.sh list        # タイマーの状態確認
scripts/insight-schedule.sh logs ~/work/myproject  # ログ確認
```

## 既存プロジェクトへの適用

1. **プロジェクト固有情報を分離**: 既存の CLAUDE.md からプロジェクト固有情報を `reports/project_context.md` に抽出
2. **CLAUDE.md を置き換え**: dist の CLAUDE.md で上書き（`@reports/project_context.md` でインクルードされる）
3. **CLAUDE.local.md をコピー**: dist の CLAUDE.local.md で上書き
4. **セッション起動**: `/persona-setup` で人格を設定
