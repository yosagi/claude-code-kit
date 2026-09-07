#!/bin/bash
# 目的: セッション終了時に会話ログをエクスポートする Claude Code hook
# 関連: work-logger スキル、ccexport コマンド
# 前提: ccexport がインストールされていること、jq が利用可能なこと

set -euo pipefail

SCRIPT_NAME="session_end.sh"
HOOKS_DIR="$HOME/.claude/hooks"
SETTINGS_FILE="$HOME/.claude/settings.json"
SESSION_LOG_DIR="$HOME/Notes/journals/claude_sessions"
REGISTRY_BASE="$HOME/Notes/claude-registry"

# 自分自身の絶対パス（ワーカーの再起動と hook のコピーに使う）
SELF="$(readlink -f "$0" 2>/dev/null || echo "$0")"

# ワーカーのログ。失敗が痕跡として残るようにする
WORKER_LOG="$HOME/.claude/session_end_worker.log"
WORKER_LOG_MAX_BYTES=$((1024 * 1024))

# 孤児リカバリで無視する更新間隔（分）
# まだ生きているセッションの残骸を横取りしないためのガード
ORPHAN_MIN_AGE_MIN=10

# 孤児リカバリを諦める経過日数
# Claude Code の会話ログ保持期間（30日）を過ぎた残骸は export が成功する見込みがないため、
# リトライせず .claude/work-logger_stale/ に退避する
ORPHAN_GIVEUP_DAYS=30
STALE_DIR_NAME="work-logger_stale"

# ログ行の識別子（ワーカー起動時に設定）
WORKER_SESSION_ID="-"

show_help() {
    cat << EOF
Usage: $SCRIPT_NAME [OPTIONS]

Claude Code SessionEnd hook - セッション終了時に会話ログをエクスポート

Options:
  --install            hook をインストール（~/.claude/hooks/ にコピー、settings.json を編集）
  --uninstall          hook をアンインストール
  --status             インストール状態を確認
  --session-log-dir    セッションログの出力先ディレクトリを表示
  --prepare <ID>       work-logger 用: ファイル名を生成し一時ファイルに書き込む
  --worker <ID> [DIR]  内部用: 実処理を行うデタッチ済みワーカー
  --help               このヘルプを表示

通常実行（hook として）:
  標準入力から JSON を読み取り、setsid で切り離したワーカーに処理を委譲します。
  ワーカーが ccexport で会話ログをエクスポートします。
  ワーカーのログ: $WORKER_LOG
  出力先: $SESSION_LOG_DIR/claude_<YYYY-MM-DD>_<session_id先頭8文字>.org

  opt-in 方式:
    プロジェクトに .claude/export_session ファイルがある場合のみエクスポート。
    ファイルがなければ何もせず終了します。

  work-logger スキルと連携する場合:
    .claude/work-logger_<session_id>.txt にファイル名が指定されていれば、
    そのパスにエクスポートし、ファイルを削除します。

EOF
}

check_dependencies() {
    local missing=()
    command -v jq >/dev/null 2>&1 || missing+=("jq")
    command -v ccexport >/dev/null 2>&1 || missing+=("ccexport")

    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "エラー: 以下のコマンドが必要です: ${missing[*]}" >&2
        return 1
    fi
}

do_install() {
    echo "SessionEnd hook をインストールします..."

    # 依存関係チェック
    check_dependencies || exit 1

    # hooks ディレクトリ作成
    if [[ ! -d "$HOOKS_DIR" ]]; then
        echo "  作成: $HOOKS_DIR"
        mkdir -p "$HOOKS_DIR"
    fi

    # sessions ディレクトリ作成
    if [[ ! -d "$SESSION_LOG_DIR" ]]; then
        echo "  作成: $SESSION_LOG_DIR"
        mkdir -p "$SESSION_LOG_DIR"
    fi

    # スクリプトをコピー
    local target="$HOOKS_DIR/$SCRIPT_NAME"
    echo "  コピー: $target"
    cp "$SELF" "$target"
    chmod +x "$target"

    # settings.json を編集
    if [[ ! -f "$SETTINGS_FILE" ]]; then
        echo "  作成: $SETTINGS_FILE"
        echo '{}' > "$SETTINGS_FILE"
    fi

    # hooks セクションが既にあるか確認
    if jq -e '.hooks.SessionEnd' "$SETTINGS_FILE" >/dev/null 2>&1; then
        echo "  警告: SessionEnd hook は既に設定されています"
        echo "  現在の設定:"
        jq '.hooks.SessionEnd' "$SETTINGS_FILE"
    else
        echo "  編集: $SETTINGS_FILE"
        local tmp=$(mktemp)
        jq --arg cmd "$HOOKS_DIR/$SCRIPT_NAME" '
            .hooks = (.hooks // {}) |
            .hooks.SessionEnd = [
                {
                    "hooks": [
                        {
                            "type": "command",
                            "command": $cmd
                        }
                    ]
                }
            ]
        ' "$SETTINGS_FILE" > "$tmp" && mv "$tmp" "$SETTINGS_FILE"
    fi

    echo ""
    echo "インストール完了！"
    echo "次回のセッション終了時から会話ログが自動エクスポートされます。"
}

do_uninstall() {
    echo "SessionEnd hook をアンインストールします..."

    # スクリプトを削除
    local target="$HOOKS_DIR/$SCRIPT_NAME"
    if [[ -f "$target" ]]; then
        echo "  削除: $target"
        rm "$target"
    fi

    # settings.json から hooks.SessionEnd を削除
    if [[ -f "$SETTINGS_FILE" ]] && jq -e '.hooks.SessionEnd' "$SETTINGS_FILE" >/dev/null 2>&1; then
        echo "  編集: $SETTINGS_FILE"
        local tmp=$(mktemp)
        jq 'del(.hooks.SessionEnd) | if .hooks == {} then del(.hooks) else . end' "$SETTINGS_FILE" > "$tmp" && mv "$tmp" "$SETTINGS_FILE"
    fi

    echo ""
    echo "アンインストール完了！"
}

do_status() {
    echo "SessionEnd hook の状態:"
    echo ""

    # スクリプトの存在確認
    local target="$HOOKS_DIR/$SCRIPT_NAME"
    if [[ -f "$target" ]]; then
        echo "  スクリプト: $target (インストール済み)"
    else
        echo "  スクリプト: 未インストール"
    fi

    # settings.json の確認
    if [[ -f "$SETTINGS_FILE" ]] && jq -e '.hooks.SessionEnd' "$SETTINGS_FILE" >/dev/null 2>&1; then
        echo "  settings.json: SessionEnd hook 設定あり"
        jq '.hooks.SessionEnd' "$SETTINGS_FILE" | sed 's/^/    /'
    else
        echo "  settings.json: SessionEnd hook 設定なし"
    fi

    # 依存関係
    echo ""
    echo "依存関係:"
    if command -v jq >/dev/null 2>&1; then
        echo "  jq: $(which jq)"
    else
        echo "  jq: 未インストール"
    fi
    if command -v ccexport >/dev/null 2>&1; then
        echo "  ccexport: $(which ccexport)"
    else
        echo "  ccexport: 未インストール"
    fi

    # sessions ディレクトリ
    echo ""
    if [[ -d "$SESSION_LOG_DIR" ]]; then
        local count=$(ls -1 "$SESSION_LOG_DIR" 2>/dev/null | wc -l)
        echo "  sessions: $SESSION_LOG_DIR ($count ファイル)"
    else
        echo "  sessions: $SESSION_LOG_DIR (未作成)"
    fi
}

# work-logger 用: ファイル名を生成し一時ファイルに書き込む
do_prepare() {
    local session_id="$1"

    if [[ -z "$session_id" ]]; then
        echo "エラー: セッション ID が指定されていません" >&2
        echo "使用法: $SCRIPT_NAME --prepare <SESSION_ID>" >&2
        exit 1
    fi

    # ccexport でプロジェクト情報を取得
    local session_info
    if ! session_info=$(ccexport session-info -s "$session_id" --json 2>/dev/null); then
        echo "エラー: セッション情報の取得に失敗しました" >&2
        exit 1
    fi

    local project_path
    project_path=$(echo "$session_info" | jq -r '.project')

    # opt-in チェック: .claude/export_session がなければスキップ
    if [[ ! -f "$project_path/.claude/export_session" ]]; then
        # opt-in されていないプロジェクトは何もしない
        exit 0
    fi

    local project_name
    project_name=$(basename "$project_path")

    # 日付を決定（03:00 未満なら前日）
    local hour
    hour=$(date '+%H')
    local date_str
    if [[ "10#$hour" -lt 3 ]]; then
        date_str=$(date -d 'yesterday' '+%Y-%m-%d')
    else
        date_str=$(date '+%Y-%m-%d')
    fi

    # 先頭8文字を取得
    local short_id="${session_id:0:8}"

    # ファイル名を生成
    local output_file="$SESSION_LOG_DIR/${project_name}_${date_str}_${short_id}.org"

    # 一時ファイルに書き込み
    local work_logger_file="$project_path/.claude/work-logger_${session_id}.txt"
    mkdir -p "$(dirname "$work_logger_file")"
    echo "$output_file" > "$work_logger_file"

    # フルパスを stdout に出力
    echo "$output_file"
}

# プロジェクトパスから registry のディレクトリ名を生成
# $HOME を省略し、/ → -, . → - で変換（session_start.sh と同じロジック）
path_to_dirname() {
    local path="$1"
    echo "${path#$HOME/}" | sed 's|/|-|g; s|\.|-|g'
}

# ワーカーのログ出力（stdout/stderr は起動側でログファイルに向けられている）
log_worker() {
    printf '%s [%s] %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$WORKER_SESSION_ID" "$*" >&2
}

# ワーカーログが肥大化したらローテートする
rotate_worker_log() {
    [[ -f "$WORKER_LOG" ]] || return 0
    local size
    size=$(stat -c %s "$WORKER_LOG" 2>/dev/null || echo 0)
    if [[ "$size" -gt "$WORKER_LOG_MAX_BYTES" ]]; then
        mv -f "$WORKER_LOG" "$WORKER_LOG.1"
    fi
}

# registry の sessions ディレクトリのパスを返す
registry_sessions_dir() {
    local project_dir="$1"
    local hostname
    hostname=$(hostname)
    local dir_name
    dir_name=$(path_to_dirname "$project_dir")
    echo "$REGISTRY_BASE/$hostname/$dir_name/sessions"
}

# ダイジェスト JSON を registry/sessions/ に書き出す
# 成功したときだけ digest ファイルを削除する（途中死したら次回リトライされる）
write_session_digest() {
    local session_id="$1"
    local project_dir="$2"
    local digest_file="$project_dir/reports/memory/work-logger-${session_id}_digest.txt"

    # digest ファイルがなければ何もしない
    if [[ ! -f "$digest_file" ]]; then
        return 0
    fi

    local digest
    digest=$(cat "$digest_file")

    # 空なら書き出さずに片付ける
    if [[ -z "$digest" ]]; then
        rm -f "$digest_file"
        return 0
    fi

    # ccexport session-info --verbose で start/end を取得
    # 失敗しても digest 本文だけは必ず書き出す
    local session_info=""
    if ! session_info=$(ccexport session-info -s "$session_id" --json --verbose 2>/dev/null); then
        session_info=""
        log_worker "session-info failed: $session_id (digest only)"
    fi

    local project_name
    project_name=$(basename "$project_dir")

    local start_time="" end_time="" turn_count="" total_duration_ms="" session_type=""
    if [[ -n "$session_info" ]]; then
        start_time=$(echo "$session_info" | jq -r '.start_time // empty')
        end_time=$(echo "$session_info" | jq -r '.end_time // empty')
        turn_count=$(echo "$session_info" | jq -r '.turn_count // empty')
        total_duration_ms=$(echo "$session_info" | jq -r '.total_duration_ms // empty')
        session_type=$(echo "$session_info" | jq -r '.session_type // empty')
    fi

    local sessions_dir
    sessions_dir=$(registry_sessions_dir "$project_dir")
    mkdir -p "$sessions_dir"

    # 一時ファイルに書いてから mv する（途中死しても 0 バイトファイルが残らない）
    local json_file="$sessions_dir/${session_id}_meta.json"
    local tmp_file="${json_file}.tmp.$$"
    if jq -n \
        --arg sid "$session_id" \
        --arg proj "$project_name" \
        --arg start "$start_time" \
        --arg end_time "$end_time" \
        --arg turns "$turn_count" \
        --arg duration "$total_duration_ms" \
        --arg stype "$session_type" \
        --arg digest "$digest" \
        '{
            session_id: $sid,
            project: $proj,
            digest: $digest
        }
        + (if $stype != "" then {session_type: $stype} else {} end)
        + (if $start != "" then {start: $start} else {} end)
        + (if $end_time != "" then {"end": $end_time} else {} end)
        + (if $turns != "" then {turns: ($turns | tonumber)} else {} end)
        + (if $duration != "" and $duration != "null" then {total_duration_ms: ($duration | tonumber)} else {} end)
        ' > "$tmp_file" && [[ -s "$tmp_file" ]]; then
        mv -f "$tmp_file" "$json_file"
        rm -f "$digest_file"
        return 0
    fi

    rm -f "$tmp_file"
    log_worker "meta write failed: $session_id (digest kept for retry)"
    return 1
}

# 会話ログ JSON を registry/sessions/ に書き出す
write_session_log() {
    local session_id="$1"
    local project_dir="$2"

    local sessions_dir
    sessions_dir=$(registry_sessions_dir "$project_dir")
    mkdir -p "$sessions_dir"

    local log_file="$sessions_dir/${session_id}_log.json"

    # 既に中身のあるものが存在すればスキップ
    if [[ -s "$log_file" ]]; then
        return 0
    fi

    # osc-tap ログがあればタイトルも含める
    local titles_args=()
    if [[ -d "$HOME/.claude/osc-logs" ]]; then
        titles_args=(--titles-dir "$HOME/.claude/osc-logs/")
    fi

    local tmp_file="${log_file}.tmp.$$"
    if ccexport export -s "$session_id" -o "$tmp_file" -f json \
        "${titles_args[@]}" >/dev/null 2>&1 && [[ -s "$tmp_file" ]]; then
        mv -f "$tmp_file" "$log_file"
        return 0
    fi

    rm -f "$tmp_file"
    log_worker "log export failed: $session_id"
    return 1
}

# 会話ログを org 形式で journals にエクスポートする
# 成功したときだけ work-logger のマーカーファイルを削除する
export_session_org() {
    local session_id="$1"
    local project_dir="$2"

    # opt-in チェック: .claude/export_session がなければ何もしない
    if [[ ! -f "$project_dir/.claude/export_session" ]]; then
        return 0
    fi

    # work-logger が指定したファイル名があれば使う
    local work_logger_file="$project_dir/.claude/work-logger_${session_id}.txt"
    local output_file=""
    if [[ -f "$work_logger_file" ]]; then
        output_file=$(cat "$work_logger_file")
    fi

    if [[ -z "$output_file" ]]; then
        local project_name short_id date_str
        project_name=$(basename "$project_dir")
        short_id="${session_id:0:8}"
        date_str=$(date '+%Y-%m-%d')
        output_file="$SESSION_LOG_DIR/${project_name}_${date_str}_${short_id}.org"
    fi

    mkdir -p "$(dirname "$output_file")"

    local titles_args=()
    if [[ -d "$HOME/.claude/osc-logs" ]]; then
        titles_args=(--titles-dir "$HOME/.claude/osc-logs/")
    fi

    local tmp_file="${output_file}.tmp.$$"
    if ccexport export -s "$session_id" -o "$tmp_file" -f org \
        "${titles_args[@]}" >/dev/null 2>&1 && [[ -s "$tmp_file" ]]; then
        mv -f "$tmp_file" "$output_file"
        rm -f "$work_logger_file"
        return 0
    fi

    rm -f "$tmp_file"
    log_worker "org export failed: $session_id (marker kept for retry)"
    return 1
}

# ORPHAN_GIVEUP_DAYS より古い残骸を .claude/work-logger_stale/ に退避する
# 戻り値 0: 退避した（呼び出し側はリトライしない）、1: まだ新しい
retire_orphan_if_stale() {
    local project_dir="$1"
    local f="$2"
    local kind="$3"   # ログ用: digest / org marker

    if [[ -z "$(find "$f" -maxdepth 0 -type f -mtime "+$ORPHAN_GIVEUP_DAYS" 2>/dev/null)" ]]; then
        return 1
    fi

    local stale_dir="$project_dir/.claude/$STALE_DIR_NAME"
    mkdir -p "$stale_dir"
    if mv -f "$f" "$stale_dir/"; then
        log_worker "retire stale orphan $kind (>${ORPHAN_GIVEUP_DAYS}d): $(basename "$f") -> .claude/$STALE_DIR_NAME/"
    else
        log_worker "failed to retire stale orphan $kind: $f"
    fi
    return 0
}

# 前回以前のセッションで処理しきれなかった残骸をリトライする
# ORPHAN_MIN_AGE_MIN 以内に更新されたものは、まだ生きているセッションの分を
# 横取りしないためスキップする
# ORPHAN_GIVEUP_DAYS より古いものはリトライせず退避する（会話ログが消えていて成功しない）
recover_orphans() {
    local project_dir="$1"
    local current_session="$2"
    local f base sid

    while IFS= read -r f; do
        [[ -n "$f" ]] || continue
        base=$(basename "$f")
        sid=${base#work-logger-}
        sid=${sid%_digest.txt}
        if [[ "$sid" == "$current_session" ]]; then
            continue
        fi
        if retire_orphan_if_stale "$project_dir" "$f" "digest"; then
            continue
        fi
        log_worker "recover orphan digest: $sid"
        write_session_digest "$sid" "$project_dir" || true
    done < <(find "$project_dir/reports/memory" -maxdepth 1 -type f \
        -name 'work-logger-*_digest.txt' -mmin "+$ORPHAN_MIN_AGE_MIN" 2>/dev/null)

    while IFS= read -r f; do
        [[ -n "$f" ]] || continue
        base=$(basename "$f")
        sid=${base#work-logger_}
        sid=${sid%.txt}
        if [[ "$sid" == "$current_session" ]]; then
            continue
        fi
        if retire_orphan_if_stale "$project_dir" "$f" "org marker"; then
            continue
        fi
        log_worker "recover orphan org export: $sid"
        export_session_org "$sid" "$project_dir" || true
    done < <(find "$project_dir/.claude" -maxdepth 1 -type f \
        -name 'work-logger_*.txt' -mmin "+$ORPHAN_MIN_AGE_MIN" 2>/dev/null)
}

resolve_project_dir() {
    # プロジェクトルートを取得する
    # hook 実行時は CLAUDE_PROJECT_DIR が設定され、session_id も必ず得られる
    local session_id="$1"

    # 1. CLAUDE_PROJECT_DIR 環境変数（hook 実行時に Claude Code が設定）
    if [[ -n "${CLAUDE_PROJECT_DIR:-}" ]]; then
        echo "$CLAUDE_PROJECT_DIR"
        return 0
    fi

    # 2. ccexport session-info（フォールバック）
    if [[ -n "$session_id" ]]; then
        local session_info
        if session_info=$(ccexport session-info -s "$session_id" --json 2>/dev/null); then
            local project
            project=$(echo "$session_info" | jq -r '.project // empty')
            if [[ -n "$project" ]]; then
                echo "$project"
                return 0
            fi
        fi
    fi

    return 1
}

# 実処理を行うワーカー（setsid で切り離されて実行される）
do_worker() {
    local session_id="$1"
    local project_dir="${2:-}"

    if [[ -z "$session_id" ]]; then
        log_worker "no session_id given"
        exit 1
    fi
    WORKER_SESSION_ID="${session_id:0:8}"

    # 依存が揃っていなければ静かに終了
    if ! command -v ccexport >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
        log_worker "missing dependencies (ccexport/jq)"
        exit 0
    fi

    # プロジェクトルートを解決
    if [[ -z "$project_dir" ]]; then
        if ! project_dir=$(resolve_project_dir "$session_id"); then
            log_worker "could not resolve project dir"
            exit 0
        fi
    fi

    # 同一プロジェクトのワーカーが重ならないようにする
    local lock_file="$project_dir/.claude/session_end_worker.lock"
    if [[ -d "$project_dir/.claude" && -w "$project_dir/.claude" ]]; then
        exec 9>"$lock_file"
        flock -w 600 9 2>/dev/null || log_worker "lock not acquired, proceeding"
    fi

    # work-logger が動いたセッションかどうか
    # --prepare が置くマーカーか、work-logger スキルが書く digest のどちらかがあれば「動いた」
    # 動いていないセッション（headless の insight、work-logger を回さずに閉じた対話セッション）は
    # 終了処理をしていないので、会話ログ JSON とバックアップだけ残して他はスキップする
    local work_logger_ran=0
    if [[ -f "$project_dir/.claude/work-logger_${session_id}.txt" \
       || -f "$project_dir/reports/memory/work-logger-${session_id}_digest.txt" ]]; then
        work_logger_ran=1
    fi

    if (( work_logger_ran )); then
        log_worker "start: $project_dir"
    else
        log_worker "start (light, no work-logger): $project_dir"
    fi

    # ダイジェスト JSON を registry に書き出す（opt-in 不要、digest がなければ何もしない）
    if (( work_logger_ran )); then
        write_session_digest "$session_id" "$project_dir" || true
    fi

    # 会話ログ JSON を registry に書き出す（opt-in 不要、ccdash が読む）
    write_session_log "$session_id" "$project_dir" || true

    # ドラフトファイルがあれば journals に追記（追記許可ホストのみ）
    if (( work_logger_ran )); then
        local process_drafts_script
        process_drafts_script="$(dirname "$SELF")/process_journal_drafts.sh"
        if [[ -x "$process_drafts_script" ]]; then
            "$process_drafts_script" || log_worker "process_journal_drafts.sh failed"
        fi
    fi

    # プロジェクト状態を registry にバックアップ（work-logger の有無を問わず実行）
    local backup_script
    backup_script="$(dirname "$SELF")/backup_project_state.sh"
    if [[ -x "$backup_script" ]]; then
        "$backup_script" "$project_dir" "$session_id" >/dev/null 2>&1 \
            || log_worker "backup_project_state.sh failed"
    fi

    if (( work_logger_ran )); then
        # 会話ログを org 形式で journals にエクスポート（opt-in のみ）
        export_session_org "$session_id" "$project_dir" || true

        # 前回以前のセッションの残骸をリトライ
        recover_orphans "$project_dir" "$session_id" || true
    fi

    log_worker "done"
}

run_hook() {
    # 標準入力から JSON を読み取り
    local input
    input=$(cat)

    # 必要な値を抽出
    local session_id
    session_id=$(echo "$input" | jq -r '.session_id // empty')

    if [[ -z "$session_id" ]]; then
        echo "エラー: session_id が見つかりません" >&2
        exit 1
    fi

    rotate_worker_log

    # Note: SessionEnd hook はプロセス終了時に約2秒で kill される既知の問題がある
    # (https://github.com/anthropics/claude-code/issues/41577)
    # そのためここでは重い処理を一切せず、実処理はワーカーに委譲して即座に終了する。
    # nohup は SIGHUP しか防げずプロセスグループへのシグナルは波及するため、
    # setsid で新しいセッション/プロセスグループに逃がす。
    setsid "$SELF" --worker "$session_id" "${CLAUDE_PROJECT_DIR:-}" \
        >>"$WORKER_LOG" 2>&1 </dev/null &
    disown
}

# メイン処理
case "${1:-}" in
    --install)
        do_install
        ;;
    --uninstall)
        do_uninstall
        ;;
    --status)
        do_status
        ;;
    --session-log-dir)
        echo "$SESSION_LOG_DIR"
        ;;
    --prepare)
        do_prepare "${2:-}"
        ;;
    --worker)
        do_worker "${2:-}" "${3:-}"
        ;;
    --help|-h)
        show_help
        ;;
    "")
        # 引数なしの場合は hook として実行
        run_hook
        ;;
    *)
        echo "不明なオプション: $1" >&2
        show_help >&2
        exit 1
        ;;
esac
