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
  --help               このヘルプを表示

通常実行（hook として）:
  標準入力から JSON を読み取り、ccexport で会話ログをエクスポートします。
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
    cp "$0" "$target"
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

# ダイジェスト JSON を registry/sessions/ に書き出す
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
    rm -f "$digest_file"

    # 空なら書き出さない
    if [[ -z "$digest" ]]; then
        return 0
    fi

    # ccexport session-info --verbose で start/end を取得
    local session_info
    if ! session_info=$(ccexport session-info -s "$session_id" --json --verbose 2>/dev/null); then
        # session-info が失敗した場合は start/end なしで書き出す
        session_info=""
    fi

    local project_name
    project_name=$(basename "$project_dir")

    local start_time end_time turn_count total_duration_ms session_type
    if [[ -n "$session_info" ]]; then
        start_time=$(echo "$session_info" | jq -r '.start_time // empty')
        end_time=$(echo "$session_info" | jq -r '.end_time // empty')
        turn_count=$(echo "$session_info" | jq -r '.turn_count // empty')
        total_duration_ms=$(echo "$session_info" | jq -r '.total_duration_ms // empty')
        session_type=$(echo "$session_info" | jq -r '.session_type // empty')
    fi

    # registry のパスを構築
    local hostname
    hostname=$(hostname)
    local dir_name
    dir_name=$(path_to_dirname "$project_dir")
    local sessions_dir="$REGISTRY_BASE/$hostname/$dir_name/sessions"

    mkdir -p "$sessions_dir"

    # JSON を書き出す
    local json_file="$sessions_dir/${session_id}_meta.json"
    jq -n \
        --arg sid "$session_id" \
        --arg proj "$project_name" \
        --arg start "${start_time:-}" \
        --arg end_time "${end_time:-}" \
        --arg turns "${turn_count:-}" \
        --arg duration "${total_duration_ms:-}" \
        --arg stype "${session_type:-}" \
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
        ' > "$json_file"
}

# 会話ログ JSON を registry/sessions/ に書き出す
write_session_log() {
    local session_id="$1"
    local project_dir="$2"

    # registry のパスを構築
    local hostname
    hostname=$(hostname)
    local dir_name
    dir_name=$(path_to_dirname "$project_dir")
    local sessions_dir="$REGISTRY_BASE/$hostname/$dir_name/sessions"

    mkdir -p "$sessions_dir"

    local log_file="$sessions_dir/${session_id}_log.json"

    # 既に存在すればスキップ
    if [[ -f "$log_file" ]]; then
        return 0
    fi

    # ccexport で JSON 形式でエクスポート
    ccexport export -s "$session_id" -o "$log_file" -f json 2>/dev/null || true
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

    # プロジェクトルートを解決
    local project_dir
    if ! project_dir=$(resolve_project_dir "$session_id"); then
        # プロジェクトルートが特定できない場合はスキップ
        exit 0
    fi

    # ダイジェスト JSON を registry に書き出す（opt-in 不要）
    write_session_digest "$session_id" "$project_dir"

    # 会話ログ JSON を registry に書き出す（opt-in 不要）
    write_session_log "$session_id" "$project_dir"

    # ドラフトファイルがあれば journals に追記（追記許可ホストのみ）
    local process_drafts_script
    process_drafts_script="$(dirname "$0")/process_journal_drafts.sh"
    if [[ -x "$process_drafts_script" ]]; then
        "$process_drafts_script" || true
    fi

    # プロジェクト状態を registry にバックアップ（nohup+disown で切り離し）
    local backup_script
    backup_script="$(dirname "$0")/backup_project_state.sh"
    if [[ -x "$backup_script" ]]; then
        nohup "$backup_script" "$project_dir" "$session_id" >/dev/null 2>&1 &
        disown
    fi

    # opt-in チェック: .claude/export_session がなければ org エクスポートはスキップ
    if [[ ! -f "$project_dir/.claude/export_session" ]]; then
        exit 0
    fi

    # work-logger からのファイル名指定を確認
    local work_logger_file="$project_dir/.claude/work-logger_${session_id}.txt"
    local output_file=""

    if [[ -f "$work_logger_file" ]]; then
        # work-logger が指定したファイル名を使用
        output_file=$(cat "$work_logger_file")
        # 使用後は削除
        rm -f "$work_logger_file"
    else
        local project_name
        project_name=$(basename "$project_dir")

        local short_id="${session_id:0:8}"
        local date_str
        date_str=$(date '+%Y-%m-%d')

        # sessions ディレクトリを確認
        mkdir -p "$SESSION_LOG_DIR"

        # ファイル名: project_YYYY-MM-DD_shortid.org
        output_file="$SESSION_LOG_DIR/${project_name}_${date_str}_${short_id}.org"
    fi

    # 出力先ディレクトリを確認
    mkdir -p "$(dirname "$output_file")"

    # ccexport を実行（osc-tap ログがあればタイトルも含める）
    # Note: SessionEnd hook はプロセス終了時に即座に kill される既知の問題があるため
    # (https://github.com/anthropics/claude-code/issues/41577)
    # nohup + disown でプロセスを切り離して実行する
    nohup ccexport export -s "$session_id" -o "$output_file" -f org \
        --titles-dir "$HOME/.claude/osc-logs/" >/dev/null 2>&1 &
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
