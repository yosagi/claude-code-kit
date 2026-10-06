# claude-code-kit

Claude Code を少しだけ楽しく使うためのセットアップキット。

CLAUDE.md / CLAUDE.local.md と周辺ツールの一式で、セッションをまたいで記憶が続く Claude Code 環境を構築します。

## 何ができるか

- **記憶の永続化**: 作業履歴・ユーザー情報が自動でファイルに残り、次のセッションに引き継がれる。「はじめまして」から始まらない継続した関係
- **タスク管理**: IDEAS → TODO → 実装ログ → 完了のライフサイクルで、セッションをまたぐ中長期タスクを管理
- **ナレッジベース**: 調査結果を KB に蓄積し、プロジェクトの知見を永続化
- **グローバル KB**: プロジェクト横断の知見を registry に蓄積し、起動時にプロジェクトの関心タグにマッチしたものだけを自動注入
- **セッション引き継ぎ**: 進行中の作業状態をファイルに残して、次のセッションでスムーズに再開
- **プロジェクト間連携**: inbox を使って別プロジェクトの Claude に依頼を送信、自動処理して結果を受け取る非同期メッセージング。マルチPC対応
- **定期洞察（insight）**: プロジェクトの状態を自動分析し、TODO/IDEAS の整理提案・知見抽出・横断的な気づきをレポート
- **自動バックアップ**: セッション終了時に記憶・タスク管理・設定ファイルを registry に自動バックアップ。次のセッション開始時に整合性チェック
- **記録の健全性チェック**: registry に溜まる会話ログ・ダイジェスト・バックアップの欠損や、同期の停止、journals のリンク切れを全ホスト横断で検出。insight のジョブとして定期実行できる
- **ステータスライン**: コンテキスト使用率、rate limits、IDEAS/TODO/inbox 件数をリアルタイム表示
- **時報**: 毎ターン現在日時を注入。時間帯に応じた挨拶や、深夜帯の作業抑制などの行動規範に反映
- **人格システム**: 多数の人格サンプルをもとに、口調・性格・フレーバーを自由に組み合わせて人格を提案。既存プロジェクトで使っている人格の分布を踏まえて、被らない方向も自動で提案
- **マルチPC自動同期**: claude-code ラッパーが起動時に設定の更新を検知し、自動インストール。CLAUDE.md / CLAUDE.local.md も自動配置・更新確認

## 外部依存

| ツール | 用途 | インストール |
|--------|------|--------------|
| **jq** | JSON パース | `sudo apt install jq` / `brew install jq` |
| **uv** | Python ツール管理 | `curl -LsSf https://astral.sh/uv/install.sh \| sh` |
| **ccexport** | セッション情報取得・ログエクスポート | `uv tool install git+https://github.com/yosagi/ccexport.git` |
| **osc-tap** | OSC シーケンスキャプチャ（任意） | `uv tool install git+https://github.com/yosagi/osc-tap.git` |
| **ファイル同期システム** | `~/Notes/claude-registry/` のPC間同期（複数PC利用時） | Syncthing / Dropbox 等、任意のもの |

`bootstrap.sh` を使えばこれらの導入からグローバル設定まで一括で行えます（ファイル同期システムを除く）。

registry（`~/Notes/claude-registry/`）はセッション情報・バックアップ・グローバル KB などの置き場で、1台で使う場合は単なるローカルディレクトリとして動作します。複数PCで使う場合は Syncthing 等でPC間同期することで、設定の自動配布・プロジェクト間連携・グローバル KB の共有がPCをまたいで機能します。

## セットアップ

### 1. 初期セットアップ（PCごとに1回）

**初回（clone から）**: キットを任意の場所に clone し、bootstrap.sh を実行します。

```bash
git clone https://github.com/yosagi/claude-code-kit.git ~/src/claude-code-kit
cd ~/src/claude-code-kit
./bootstrap.sh   # 依存ツール導入 + グローバル設定を一括インストール
```

これで以下がインストールされます：
- 依存ツール（jq, ccexport, osc-tap）
- Ubuntu 26.04 以降の sandbox 前提（bwrap の AppArmor local override。後述「保守用ツール」の `setup_bwrap_apparmor.sh`。非該当環境ではスキップ）
- Skills（briefing, inbox, inbox-send, persona-setup, insight, insight-status, stocktake, note-logger, global-kb, registry-health 等）
- Hooks（SessionStart: registry 登録、SessionEnd: ログエクスポート・バックアップ・記憶ドラフト処理、UserPromptSubmit: 時報）
- Status Line（コンテキスト使用率・rate limits 表示）
- Sandbox 例外設定、許可設定
- claude-code ラッパー（後述）と起動時コンテキスト組み立てスクリプト

最後に `update-registry.sh` が実行され、キットの内容が `~/Notes/claude-registry/dist/` に配置されます。ここが以降の自動インストール（auto-install）の配布元になります。

**2台目以降（registry 同期済みPC）**: `~/Notes/claude-registry/` を Syncthing 等で同期していれば clone は不要で、registry 内の bootstrap.sh を実行するだけです。

```bash
~/Notes/claude-registry/dist/bootstrap.sh
```

既存の `~/.claude/settings.json` は自動的に `settings.json.bak` にバックアップされます。

**キットの更新**: clone したディレクトリで pull して `update-registry.sh` を実行します。registry に配置され、他のPCでも次回の `claude-code` 起動時に自動インストールされます（依存ツールも更新したい場合は代わりに `./bootstrap.sh` を再実行）。

```bash
cd ~/src/claude-code-kit
git pull && ./update-registry.sh
```

fork を作って自分向けの修正版を運用する場合も、pull 元が fork になるだけでこの手順のまま成り立ちます。

### 2. プロジェクトのセットアップ

`claude-code` ラッパー経由で起動すると、CLAUDE.md / CLAUDE.local.md が自動配置されます。

```bash
cd /path/to/your/project

# Claude Code を起動（CLAUDE.md / CLAUDE.local.md が自動配置される）
claude-code
```

ラッパーを使わない場合は手動でコピーしてください：

```bash
cp /path/to/dist/CLAUDE.md .
cp /path/to/dist/CLAUDE.local.md .
cp /path/to/dist/work_in_progress.md .
```

初回起動時に `/persona-setup` スキルが人格セットアップを案内します。
人格を定義するか素のClaudeで進めるかを選択し、定義する場合は既存人格の分布を踏まえた提案を受けられます。
完了すると `reports/` 以下にプロジェクト構造が作成されます。

あわせて `.git/info/exclude` も自動調整されます（git リポジトリの場合のみ）。追加されるのは次の3群です。

- キットが使うファイル群（`reports/` `scratch/` `tmp/` `.claude/` とルート直下の `work_in_progress.md` `CLAUDE.md` `CLAUDE.local.md` `.no-claude-md-sync`）
- sandbox 実行時にプロジェクトルートへ生える一時 dotfile（`.bashrc` `.profile` `.gitconfig` 等）
- `.venv/` と JetBrains IDE のユーザー固有ファイル（`.idea/**/workspace.xml` 等）

書き込み先が共有物の `.gitignore` ではなく、このクローンにだけ効く `.git/info/exclude` なのは、キットの利用が個人の作業環境の話であってプロジェクトの共有ファイルに痕跡を残すべきでないためです。既存のエントリ（`.gitignore` 側で既に無視されているものを含む）は重複追記されないため、何度実行しても結果は変わりません。worktree から実行した場合も本体の `.git/info/exclude` に書かれます。キットのファイル群は個人の作業データで、セッション終了時に registry へ自動バックアップされるので、git 管理から外すのが既定の運用です。`CLAUDE.md`（ワークフロー定義）をチームで共有したい場合は、exclude から該当行を削除してコミットしてください。

**既存プロジェクトへの適用**: これらのファイルを既にコミットしてしまっているプロジェクトには、保守用ツール `setup_git_exclude.sh` を使います（後述「保守用ツール」）。`init-project.sh` は内部でこのツールを `--no-untrack` で呼ぶため、新規セットアップ時に追跡済みファイルがあっても一覧を表示するだけで外しません。

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

## claude-code ラッパー

`claude` の代わりに使う起動ラッパーです。環境の同期からプロジェクトの初期配置までを起動時に済ませるため、常用を推奨します。起動時に以下を順に行います：

1. **auto-install**: registry の dist が更新されていたら `setup_global.sh --install` を自動実行（マルチPC同期）
2. **プロジェクトディレクトリガード**: cwd に `.claude/` と `reports/` が揃っていない場所での対話起動時は、意図しないプロジェクトの発生を防ぐため確認プロンプトを出す。新規プロジェクトとして続行する場合は、セッションログエクスポートの opt-in（`.claude/export_session` の作成）もその場で選択できる
3. **CLAUDE.md / CLAUDE.local.md 同期**: 未配置なら dist から自動コピー、更新があれば対話的に確認（`.no-claude-md-sync` で無効化）
4. **起動時コンテキスト組み立て**: グローバル KB から関心タグにマッチした知見を `tmp/global_kb_context.md` に書き出す（後述）
5. **osc-tap 経由の起動**: OSC シーケンスをキャプチャし、セッションタイトルの記録などに利用。osc-tap 未インストール時や stdout が TTY でないとき（systemd service 等）は素の `claude` を直接起動

ラッパー固有のオプション：

| オプション | 動作 |
|-----------|------|
| `--list-versions` | インストール済み Claude Code バージョン一覧 |
| `--enforce-version VERSION` | 指定バージョンで起動（regression 回避用） |
| `--no-osc-tap` | osc-tap をバイパスして素の claude を起動 |
| `--show-context` | 起動時コンテキストを表示して終了 |
| `--no-context` | 起動時コンテキスト組み立てをスキップ |

既知の問題があるバージョンはスクリプト内の `VERSION_BLACKLIST` に登録でき、該当バージョンがデフォルトで選ばれる場合は最新の問題ないバージョンに自動フォールバックします。

## グローバル KB

プロジェクト横断で再利用する知見を registry に蓄積し、各プロジェクトの関心にマッチしたものだけを起動時に自動注入する仕組みです。

- 知見は `~/Notes/claude-registry/<ホスト名>/kb/*.md` に置き、frontmatter で `tags` と `inject`（`full`: 全文注入 / `index`: タイトル+パスのみ列挙）を指定する
- 関心タグはホスト単位（`<ホスト名>/kb_interests`）とプロジェクト単位（`reports/project_context.md` の `kb_interests:`）で指定でき、両者の和が有効になる
- claude-code ラッパーが起動時に `build_startup_context.py` でマッチした知見を `tmp/global_kb_context.md` に組み立て、CLAUDE.md の `@` インクルードで読み込まれる
- 知見の記録・更新には `/global-kb` スキルを使う

複数PCで registry を同期していれば、全ホストの `kb/` が横断的に読まれ、どのPCで記録した知見も共有されます（同名ファイルは mtime の新しい方を採用）。

## 保守用ツール

記録が静かに欠けていないかを点検するツールを `~/.claude/scripts/` に配置します（`setup_global.sh --install`）。

### check_registry_health.py

registry 全体（同期されている全ホスト分）を走査し、次を報告します。
出力の読み方（どの節がノイズで、何が要対応か）と修復手順は `/registry-health` スキルが持っています。
手で叩くより、スキルに読ませたほうが次の一手まで出ます。

| 節 | 内容 |
|----|------|
| [1] | `_log.json` の欠損。セッション終了時のエクスポートが失敗した痕跡 |
| [2] | digest 無しで終わった対話セッション（work-logger を実行せずに閉じたもの。参考値） |
| [3] | 旧形式レコードの新顔。書き込み経路が壊れた兆候 |
| [4] | 壊れたファイル（0 バイト・パース不能・`.tmp.<pid>` 残骸）と、meta の無い log |
| [5] | ホストの鮮度。同期停止や hook 不調の検出 |
| [6] | バックアップ停滞。セッションは続いているのに `states/` だけ止まっているプロジェクト |
| [7] | journals の会話ログリンク（`check_journal_links.sh` を呼ぶ） |

```bash
~/.claude/scripts/check_registry_health.py              # 前回チェック以降の差分
~/.claude/scripts/check_registry_health.py --since all -v   # 全期間・省略なし
~/.claude/scripts/check_registry_health.py --fix        # 自ホスト分の欠損 log を再生成
~/.claude/scripts/check_registry_health.py --json       # 機械可読出力
```

既定の `--since last` は、前回の結果（`<registry>/<ホスト名>/registry_health.json`）と比べて
**新しく発生した問題だけ**を「新規」として立てます。既知の問題は「継続」に畳まれます。

`--fix` が直せるのは自ホスト分だけです。会話ログの実体はそのホストにしかないため、
他ホストの欠損は当該ホスト上で実行する必要があります。

保持期間を過ぎて会話ログが消えているセッションは、`--fix` が復旧不能マーカー
（`<セッションID>_log.unrecoverable`）をセッションの隣に残します。以後その欠損は一覧から外れ、
件数だけが表示されます。マーカーをセッションと同じ場所に置くのは、状態ファイルがホストごとで
他ホストからは読まれないのに対し、**マーカーはどのホストから走査しても同じ判断になる**ためです。
もう一度試すときは `--retry-unrecoverable` を付けます。別経路で会話ログが復活したマーカーは
次回の実行時に自動で片付きます。

`reports/jobs/` にジョブ定義を置けば、定期洞察（insight）のたびに自動で回せます。
その場合は `--fix` を付けず、修復は `/insight-review` の場で判断するとよいでしょう。

### check_journal_links.sh

journals 内の会話ログリンク（`[[file:claude_sessions/...]]`）が実在するかを確認します。
リンク切れのうち、セッション ID が一致するファイルが見つかるものは `--fix` でリネーム修復します。

### setup_git_exclude.sh

キット関連ファイル（`reports/` `scratch/` `tmp/` `.claude/` `CLAUDE.md` 等、「init-project.sh」の節で挙げた3群）を
対象プロジェクトの `.git/info/exclude` に登録し、既に追跡済みになっているものを index から外します
（`git rm --cached`。作業ツリーのファイルは残り、次の commit でリポジトリから消えます。commit はしません）。
キット導入前からあるプロジェクトに後から適用するための道具で、`.gitignore` には触りません。

```bash
~/.claude/scripts/setup_git_exclude.sh [PROJECT_ROOT] --dry-run     # 何が起きるか確認
~/.claude/scripts/setup_git_exclude.sh [PROJECT_ROOT]               # 登録 + 追跡解除
~/.claude/scripts/setup_git_exclude.sh [PROJECT_ROOT] --no-untrack  # 登録のみ（追跡済みは一覧表示）
```

追跡から外す対象は、キットのパターンに当たる追跡済みファイルだけです（`git ls-files -i` にキットのパターンだけを
渡して判定するため、プロジェクトの `.gitignore` が無視しているものを force-add してある場合などは巻き込みません）。
`CLAUDE.md` をチームで共有するために意図的に追跡しているプロジェクトでは `--no-untrack` を使ってください。
worktree から実行すると exclude は本体側に書かれ、index は worktree 自身のものが対象になります。

### setup_bwrap_apparmor.sh

Ubuntu 26.04 以降で Claude Code の Bash sandbox が起動しない問題の手当てです。
26.04 の apparmor は `/etc/apparmor.d/bwrap-userns-restrict` を既定で読み込み、bwrap の子プロセスを
`unpriv_bwrap` プロファイルに落として全能力を奪います。Claude Code の sandbox は bwrap の中でもう一段
userns を作るため、そこで拒否されてどのコマンドも即座に失敗します。

```
apply-seccomp: write /proc/self/setgroups (nested userns is capability-restricted; caller must provide CAP_SYS_ADMIN): Permission denied
```

このツールは `/etc/apparmor.d/local/bwrap-userns-restrict` に高優先の `ix` 遷移を置いて子を `bwrap` プロファイルに
留め、プロファイルを再読込します（sudo を求めます）。配布プロファイル本体は触らず、`local/` はパッケージ更新でも
保全されます。適用後に bwrap 越しの nested userns が実際に成立するかを実測します。

```bash
~/.claude/scripts/setup_bwrap_apparmor.sh --status   # 適用不要 / 適用済み / 要適用 を表示
~/.claude/scripts/setup_bwrap_apparmor.sh --dry-run  # 何が起きるか確認
~/.claude/scripts/setup_bwrap_apparmor.sh            # 適用（何度実行しても結果は同じ）
```

`bootstrap.sh` が新PC セットアップ時に呼びます。配布プロファイルが無い環境（24.04 以前、他ディストロ、macOS）や
AppArmor が無効な環境では何もしません。既にセットアップ済みのPCを 26.04 に上げた場合は、上のコマンドを手で一度
実行してください（sudo が要るため auto-install からは呼びません）。

24.04 で `kernel.apparmor_restrict_unprivileged_userns = 1` の環境は別の問題（bwrap 自体に userns 許可が無い）で、
公式ドキュメント（Sandboxing の Ubuntu 24.04 節）の `/etc/apparmor.d/bwrap` プロファイルが要ります。このツールの範囲外です。

## ステータスラインに部品を足す（statusline.d）

ステータスラインは、枠組みの `~/.claude/statusline.sh` と部品で構成されています。枠組みの役目は、Claude Code から受け取った入力 JSON を部品に配り、部品が返した断片を ` | ` でつなぐことだけです。外部のツールは、ファイルを置くだけで部品を足せます。

```
~/.claude/statusline.d/
├── kit/        # キット同梱の表示部品（setup_global.sh が管理。手で触らない）
├── segments/   # 外部の表示部品
└── sinks/      # 外部の吸い出し部品
```

登録は実行ファイルを置くこと、解除は消すことです。設定ファイルの編集はありません。実行権の無いファイルは無視されます。

| | `segments/` | `sinks/` |
|---|---|---|
| 用途 | ステータスラインに表示を足す | 入力の値を外に持ち出す（表示はしない） |
| 呼ばれ方 | 描画のたびに同期実行。stdin に入力 JSON | 描画のたびに `setsid` で切り離して実行。stdin に入力 JSON |
| 出力 | stdout の 1 行目が断片になる。空なら何も足されない | 捨てられる |
| 遅いとき | 0.3 秒で打ち切られ、その断片は落ちる | 本体は待たない |
| 失敗したとき | 非 0 終了ならその断片は落ちる | 本体に影響しない |

- **並び順**: `kit/` と `segments/` はファイル名でまとめて並べます。キットの部品は `10-location`（モデル・プロジェクト）、`20-usage`（コンテキスト・rate limits）、`40-inbox`、`50-items`（IDEAS / TODO）、`90-wezterm-uservar` です。間に入れたいときは `30-name` のように番号を付けてください
- **差分の判定は部品の責任です**。ステータスラインは頻繁に呼ばれるので、sink が値を書き出すなら、前回から変わったときだけ書くようにしてください
- **端末を触る処理は `sinks/` に置けません**。切り離されるため親プロセスをたどれず、pty を特定できないからです。そうした処理は、何も出力しない segment として `segments/` に置いてください
- **インストーラから登録する場合**: `--install` でファイルを置き、`--uninstall` で消してください。キットのアンインストールは `kit/` だけを消し、`segments/` と `sinks/` には触れません
- 入力 JSON の項目は公式ドキュメント（statusline の Available data）を参照してください

## キット外のスキル・hook を配布する（dist-extras）

キットに同梱しない手元のスキルや hook を、キットと同じ経路で全PCに配布できます。キットが知るのは配置の規約だけで、中身には関知しません。

registry に「配布経路」を作り、その下に配布物を置きます。経路は複数持てるので、配布元が増えても同じ規約のまま扱えます。

```
~/Notes/claude-registry/dist-extras/<経路名>/
├── skills/<スキル名>/    # スキル本体
├── installers/<ファイル> # 自分をインストールする実行ファイル
├── deprecated            # 廃止したスキル名・インストーラ名（1行1件、# 以降はコメント）
└── .extras-stamp         # 更新印（update-extras.sh が書く）
```

`installers/` は、スキル以外のもの（hook など）を配るための口です。各PCで `--install` を付けて実行されるので、`settings.json` への hook 登録のように配置以外の作業が要るものも配れます。キットは登録先のイベントを知らずに済み、配布物側が自分の要件を知っている形になります。

インストーラに求められる契約は次の2つです。

- `--install` / `--uninstall` を受け付ける
- `--install` が**冪等**であること（更新のたびに全インストーラの `--install` が走ります）

配信は発信元のディレクトリを指定して実行します。

```bash
./update-extras.sh <経路名> <発信元ディレクトリ>
```

発信元は `skills/` と `installers/` を切った構造で置きます。どちらも無い場合は、直下のディレクトリをすべてスキルとみなす従来形式として扱われます。任意で `deprecated` ファイルを直下に置けます。

他のPCでは、次回の `claude-code` 起動時に `.extras-stamp` の差分が検出され、自動インストールされます（キット本体の auto-install と同じ仕組みで、判定は経路ごとに独立）。

**廃止するとき**は、発信元から消すだけでは他のPCに伝わりません。registry はファイル同期で配られるため、「消された」のか「まだ届いていない」のか区別できないからです。`deprecated` に名前を書いて配信してください。スキルなら本体とそれが登録した sandbox の除外設定が、インストーラなら `--uninstall` の実行がそれぞれ各PCで行われます（インストーラは経路から消えた後も撤去できるよう、各PCの `~/.claude/extras-installers/<経路名>/` に複製が保持されています）。

```
# deprecated の例
old-skill    # new-skill に統合 (2026-08-27)
```

廃止リストは原則として消さずに残します（全PCが処理し終えたかを知る術がないため）。1行のテキストなので蓄積しても問題になりません。

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
| データ | `registry/<ホスト名>/kb/` | プロジェクト横断の知見（グローバル KB） |

ワークフロー側は claude-code-kit の更新で上書きでき、データ側はプロジェクトやユーザーごとに独立して管理されます。

### ハードコードされたディレクトリ

以下のディレクトリパスがスクリプト内にハードコードされています。

| パス | 用途 |
|------|------|
| `~/Notes/claude-registry/` | セッション情報、バックアップ、ドラフト、グローバル KB。Syncthing 等でPC間同期する想定 |
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
│   │   ├── backup_project_state.sh   # reports/ バックアップ（session_end から起動）
│   │   └── time_awareness.sh         # 時報（UserPromptSubmit で現在日時を注入）
│   ├── skills/
│   │   ├── global-kb/               # グローバル KB への知見の記録・更新
│   │   ├── inbox/                    # inbox 受信・既読・完了
│   │   ├── inbox-send/              # inbox 送信・検索・自動処理起動
│   │   ├── inbox-process/           # inbox 自動処理
│   │   ├── inbox-process-ephemeral/ # inbox 自動処理（軽量版）
│   │   ├── insight/                 # 定期洞察レポート生成
│   │   ├── insight-review/          # insight 提案の対話的処理
│   │   ├── stocktake/               # IDEAS/TODO/KB の棚卸し
│   │   ├── persona-setup/           # 人格セットアップ（init-project.sh で構造・.git/info/exclude 初期化）
│   │   ├── memory-compact/          # 記憶ファイルの圧縮・要約
│   │   ├── note-logger/             # 経緯・背景の journals 記録
│   │   └── work-logger/             # 作業ログの journals 記録
│   ├── statusline.sh                # ステータスラインの枠組み（→「ステータスラインに部品を足す」参照）
│   ├── statusline.d/kit/            # ステータスラインのキット部品
│   └── export_session/              # セッションログ opt-in フラグ（テンプレート）
├── scripts/
│   ├── claude-code                  # 起動ラッパー（→「claude-code ラッパー」参照）
│   ├── build_startup_context.py     # 起動時コンテキスト組み立て（グローバル KB 注入）
│   ├── insight-schedule.sh          # insight 定期実行の管理（systemd user timer）
│   ├── check_registry_health.py     # registry の健全性検査（→「保守用ツール」参照）
│   ├── check_journal_links.sh       # journals の会話ログリンク検査・修復
│   ├── setup_git_exclude.sh         # キット関連ファイルの .git/info/exclude 登録と追跡解除
│   └── setup_bwrap_apparmor.sh      # Ubuntu 26.04 以降の bwrap AppArmor 手当て（sandbox 起動不能の回避）
├── CLAUDE.md                        # [プロジェクト] ワークフロー定義
├── CLAUDE.local.md                  # [プロジェクト] 人格セットアップ用（全プロジェクト同一）
├── work_in_progress.md              # [プロジェクト] 進行中の作業状態
├── LICENSE
├── bootstrap.sh                     # 初期セットアップ（依存ツール + グローバル設定）
├── update-registry.sh               # キット内容を registry に配置（更新の配布元）
├── update-extras.sh                 # キット外のスキル・hook を registry に配置（dist-extras）
├── setup_global.sh                  # グローバル設定のインストーラ
└── install-skill.sh                 # スキル個別インストーラ（--uninstall で削除）
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

新規プロジェクトを claude-code ラッパー経由で起動した場合は、プロジェクトディレクトリガードの確認プロンプトでこのフラグをその場で作成できます。

出力先を変更する場合は `~/.claude/hooks/session_end.sh` の `SESSION_LOG_DIR` を編集してください。

## 既存プロジェクトへの適用

1. **プロジェクト固有情報を分離**: 既存の CLAUDE.md からプロジェクト固有情報を `reports/project_context.md` に抽出
2. **CLAUDE.md を置き換え**: dist の CLAUDE.md で上書き（`@reports/project_context.md` でインクルードされる）
3. **CLAUDE.local.md をコピー**: dist の CLAUDE.local.md で上書き
4. **セッション起動**: `/persona-setup` で人格を設定
