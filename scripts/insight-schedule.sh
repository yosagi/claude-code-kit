#!/bin/bash
# 目的: プロジェクトごとの insight 定期実行を systemd user timer で管理する
# 関連: /insight スキル、stocktake スキル
# 前提: systemd --user が利用可能、claude コマンドにパスが通っている

set -euo pipefail

SYSTEMD_DIR="$HOME/.config/systemd/user"
UNIT_PREFIX="insight"

usage() {
    cat <<'EOF'
Usage: insight-schedule.sh <command> [options]

Commands:
  enable <project-path> [--schedule <spec>]   定期実行を有効化
  disable <project-path>                      定期実行を無効化
  list                                        有効なタイマー一覧
  run <project-path>                          手動で即時実行
  logs <project-path> [-f]                    実行ログを表示

Schedule spec:
  weekly    毎週月曜 3:00（デフォルト）
  daily     毎日 3:00
  <cron式>  OnCalendar 形式（例: "Mon *-*-* 03:00:00"）

Examples:
  insight-schedule.sh enable ~/work/ccdash
  insight-schedule.sh enable ~/work/lab --schedule daily
  insight-schedule.sh enable ~/work/wip --schedule "Mon *-*-* 05:00:00"
  insight-schedule.sh disable ~/work/ccdash
  insight-schedule.sh list
  insight-schedule.sh run ~/work/ccdash
  insight-schedule.sh logs ~/work/ccdash
  insight-schedule.sh logs ~/work/ccdash -f
EOF
    exit 1
}

# プロジェクトパスからユニット名用の識別子を生成
# ~/work/ccdash → work-ccdash
# ~/.config/wezterm → -config-wezterm
path_to_unit_name() {
    local path="$1"
    # $HOME を除去し、/ → -、. → - に変換、先頭の - を除去
    local name="${path#"$HOME/"}"
    name="${name//\//-}"
    name="${name//./-}"
    echo "$name"
}

# プロジェクトパスを正規化
resolve_project_path() {
    local path="$1"
    # ~ を展開
    path="${path/#\~/$HOME}"
    # 末尾の / を除去
    path="${path%/}"
    # 絶対パスに変換
    if [[ ! "$path" = /* ]]; then
        path="$(cd "$path" 2>/dev/null && pwd)"
    fi
    echo "$path"
}

# スケジュール指定を OnCalendar 形式に変換
resolve_schedule() {
    local spec="${1:-weekly}"
    case "$spec" in
        weekly)  echo "Mon *-*-* 03:00:00" ;;
        daily)   echo "*-*-* 03:00:00" ;;
        *)       echo "$spec" ;;
    esac
}

# claude コマンドのパスを取得
# version blacklist を効かせるため claude-code wrapper を優先
find_claude() {
    if command -v claude-code &>/dev/null; then
        command -v claude-code
    elif command -v claude &>/dev/null; then
        command -v claude
    elif [[ -x "$HOME/.claude/local/claude" ]]; then
        echo "$HOME/.claude/local/claude"
    else
        echo "ERROR: claude コマンドが見つかりません" >&2
        exit 1
    fi
}

cmd_enable() {
    local project_path=""
    local schedule_spec="weekly"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --schedule) schedule_spec="$2"; shift 2 ;;
            *)
                if [[ -z "$project_path" ]]; then
                    project_path="$1"; shift
                else
                    echo "ERROR: 不明な引数: $1" >&2; exit 1
                fi
                ;;
        esac
    done

    [[ -z "$project_path" ]] && { echo "ERROR: プロジェクトパスを指定してください" >&2; exit 1; }

    project_path="$(resolve_project_path "$project_path")"
    [[ ! -d "$project_path" ]] && { echo "ERROR: ディレクトリが存在しません: $project_path" >&2; exit 1; }

    local unit_name="$(path_to_unit_name "$project_path")"
    local on_calendar="$(resolve_schedule "$schedule_spec")"
    local claude_cmd="$(find_claude)"

    mkdir -p "$SYSTEMD_DIR"

    # .service ファイルを生成
    cat > "$SYSTEMD_DIR/${UNIT_PREFIX}-${unit_name}.service" <<SERVICEEOF
[Unit]
Description=Insight report for ${project_path}

[Service]
Type=oneshot
WorkingDirectory=${project_path}
ExecStart=${claude_cmd} -p --permission-mode acceptEdits "/insight"
Environment=HOME=${HOME}
# タイムアウト: insight は時間がかかる場合がある
TimeoutStartSec=1800
SERVICEEOF

    # .timer ファイルを生成
    cat > "$SYSTEMD_DIR/${UNIT_PREFIX}-${unit_name}.timer" <<TIMEREOF
[Unit]
Description=Insight schedule for ${project_path}

[Timer]
OnCalendar=${on_calendar}
# 起動時に前回実行を確認し、逃したスケジュールがあれば実行
Persistent=true
# 全プロジェクトが同時に走らないようランダム遅延（insight は数分かかるため広めに）
RandomizedDelaySec=7200

[Install]
WantedBy=timers.target
TIMEREOF

    # systemd に反映
    systemctl --user daemon-reload
    systemctl --user enable --now "${UNIT_PREFIX}-${unit_name}.timer"

    echo "有効化: $project_path"
    echo "  スケジュール: $on_calendar"
    echo "  ユニット: ${UNIT_PREFIX}-${unit_name}.{timer,service}"
    echo ""
    systemctl --user status "${UNIT_PREFIX}-${unit_name}.timer" --no-pager 2>/dev/null || true
}

cmd_disable() {
    local project_path="$1"
    [[ -z "$project_path" ]] && { echo "ERROR: プロジェクトパスを指定してください" >&2; exit 1; }

    project_path="$(resolve_project_path "$project_path")"
    local unit_name="$(path_to_unit_name "$project_path")"
    local timer="${UNIT_PREFIX}-${unit_name}.timer"
    local service="${UNIT_PREFIX}-${unit_name}.service"

    if [[ ! -f "$SYSTEMD_DIR/$timer" ]]; then
        echo "ERROR: タイマーが見つかりません: $timer" >&2
        exit 1
    fi

    systemctl --user disable --now "$timer" 2>/dev/null || true
    rm -f "$SYSTEMD_DIR/$timer" "$SYSTEMD_DIR/$service"
    systemctl --user daemon-reload

    echo "無効化: $project_path"
}

cmd_list() {
    echo "=== insight タイマー一覧 ==="
    echo ""

    # systemd のタイマー一覧から insight- で始まるものを表示
    systemctl --user list-timers "${UNIT_PREFIX}-*" --no-pager 2>/dev/null || true

    echo ""
    echo "--- ユニットファイル ---"
    local found=0
    for timer_file in "$SYSTEMD_DIR"/${UNIT_PREFIX}-*.timer; do
        [[ -f "$timer_file" ]] || continue
        found=1
        local base="$(basename "$timer_file" .timer)"
        local service_file="$SYSTEMD_DIR/${base}.service"
        local project_dir=""
        if [[ -f "$service_file" ]]; then
            project_dir="$(grep '^WorkingDirectory=' "$service_file" | cut -d= -f2)"
        fi
        local schedule="$(grep '^OnCalendar=' "$timer_file" | cut -d= -f2)"
        echo "  $project_dir — $schedule"
    done
    if [[ $found -eq 0 ]]; then
        echo "  (なし)"
    fi
}

cmd_run() {
    local project_path="$1"
    [[ -z "$project_path" ]] && { echo "ERROR: プロジェクトパスを指定してください" >&2; exit 1; }

    project_path="$(resolve_project_path "$project_path")"
    local unit_name="$(path_to_unit_name "$project_path")"
    local service="${UNIT_PREFIX}-${unit_name}.service"

    if [[ ! -f "$SYSTEMD_DIR/$service" ]]; then
        echo "ERROR: サービスが見つかりません: $service" >&2
        echo "先に enable してください" >&2
        exit 1
    fi

    echo "手動実行: $project_path"
    systemctl --user start "$service"
    echo "起動しました。ログ: journalctl --user-unit=$service -f"
}

cmd_logs() {
    local project_path="$1"
    [[ -z "$project_path" ]] && { echo "ERROR: プロジェクトパスを指定してください" >&2; exit 1; }
    shift

    project_path="$(resolve_project_path "$project_path")"
    local unit_name="$(path_to_unit_name "$project_path")"
    local service="${UNIT_PREFIX}-${unit_name}.service"

    journalctl --user-unit="$service" --no-pager "$@"
}

# メインルーティング
[[ $# -lt 1 ]] && usage

command="$1"; shift
case "$command" in
    enable)  cmd_enable "$@" ;;
    disable) cmd_disable "$@" ;;
    list)    cmd_list ;;
    run)     cmd_run "${1:-}" ;;
    logs)    cmd_logs "${1:-}" "$@" ;;
    -h|--help|help) usage ;;
    *)       echo "ERROR: 不明なコマンド: $command" >&2; usage ;;
esac
