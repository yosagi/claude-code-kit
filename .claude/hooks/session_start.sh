#!/bin/bash
# 目的: セッション開始時にプロジェクト情報を registry に登録する
# 関連: マルチPC対応（inbox リモート送信、ccdash セッションログ共有）
# 前提: ~/Notes が Syncthing 等で同期されていること

set -euo pipefail

SCRIPT_NAME="session_start.sh"
HOOKS_DIR="$HOME/.claude/hooks"
SETTINGS_FILE="$HOME/.claude/settings.json"
REGISTRY_BASE="$HOME/Notes/claude-registry"

show_help() {
    cat << EOF
Usage: $SCRIPT_NAME [OPTIONS]

Claude Code SessionStart hook - プロジェクト情報を registry に登録

Options:
  --install     hook をインストール
  --uninstall   hook をアンインストール
  --status      インストール状態を確認
  --help        このヘルプを表示

通常実行（hook として）:
  標準入力から JSON を読み取り、プロジェクト情報を registry に登録します。
  登録先: $REGISTRY_BASE/<hostname>/<dir-name>/project_title.txt

Registry 構造:
  ~/Notes/claude-registry/
  ├── <hostname>/
  │   ├── <dir-name>/
  │   │   └── project_title.txt   (1行目: タイトル, 2行目: 実パス)
  │   └── .../
  └── .../

EOF
}

# プロジェクトパスから registry のディレクトリ名を生成
# $HOME を省略し、/ → -, . → - で変換
path_to_dirname() {
    local path="$1"
    echo "${path#$HOME/}" | sed 's|/|-|g; s|\.|-|g'
}

resolve_project_dir() {
    local session_id="$1"

    # 1. CLAUDE_PROJECT_DIR 環境変数（hook 実行時に Claude Code が設定）
    if [[ -n "${CLAUDE_PROJECT_DIR:-}" ]]; then
        echo "$CLAUDE_PROJECT_DIR"
        return 0
    fi

    # 2. ccexport session-info（フォールバック）
    if [[ -n "$session_id" ]] && command -v ccexport >/dev/null 2>&1; then
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

register_project() {
    local project_dir="$1"
    local hostname
    hostname=$(hostname)

    local dir_name
    dir_name=$(path_to_dirname "$project_dir")

    local registry_dir="$REGISTRY_BASE/$hostname/$dir_name"
    local title_src="$project_dir/reports/project_title.txt"

    # project_title.txt がなければ何もしない
    if [[ ! -f "$title_src" ]]; then
        return 0
    fi

    # registry ディレクトリ作成
    mkdir -p "$registry_dir"

    # パス付き project_title.txt を生成（1行目: タイトル, 2行目: 実パス）
    local tmpfile
    tmpfile=$(mktemp)
    { head -1 "$title_src"; echo "$project_dir"; } > "$tmpfile"

    # 差分があるときだけコピー（Syncthing の無駄な同期を避ける）
    if ! diff -q "$tmpfile" "$registry_dir/project_title.txt" >/dev/null 2>&1; then
        cp "$tmpfile" "$registry_dir/project_title.txt"
    fi
    rm -f "$tmpfile"

    # persona_config.md を registry にコピー（人格一覧用）
    local config_src="$project_dir/reports/personas/config.md"
    if [[ -f "$config_src" ]]; then
        if ! diff -q "$config_src" "$registry_dir/persona_config.md" >/dev/null 2>&1; then
            cp "$config_src" "$registry_dir/persona_config.md"
        fi
    fi
}

run_hook() {
    local input
    input=$(cat)

    local session_id
    session_id=$(echo "$input" | jq -r '.session_id // empty')

    # プロジェクトルートを解決
    local project_dir
    if ! project_dir=$(resolve_project_dir "$session_id"); then
        exit 0
    fi

    # registry に登録
    register_project "$project_dir"
}

do_install() {
    echo "SessionStart hook をインストールします..."

    mkdir -p "$HOOKS_DIR"

    local target="$HOOKS_DIR/$SCRIPT_NAME"
    echo "  コピー: $target"
    cp "$0" "$target"
    chmod +x "$target"

    # settings.json を編集
    if [[ ! -f "$SETTINGS_FILE" ]]; then
        echo '{}' > "$SETTINGS_FILE"
    fi

    if jq -e '.hooks.SessionStart' "$SETTINGS_FILE" >/dev/null 2>&1; then
        echo "  警告: SessionStart hook は既に設定されています"
        jq '.hooks.SessionStart' "$SETTINGS_FILE"
    else
        echo "  編集: $SETTINGS_FILE"
        local tmp=$(mktemp)
        jq --arg cmd "$HOOKS_DIR/$SCRIPT_NAME" '
            .hooks = (.hooks // {}) |
            .hooks.SessionStart = [
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
}

do_uninstall() {
    echo "SessionStart hook をアンインストールします..."

    local target="$HOOKS_DIR/$SCRIPT_NAME"
    if [[ -f "$target" ]]; then
        echo "  削除: $target"
        rm "$target"
    fi

    if [[ -f "$SETTINGS_FILE" ]] && jq -e '.hooks.SessionStart' "$SETTINGS_FILE" >/dev/null 2>&1; then
        echo "  編集: $SETTINGS_FILE"
        local tmp=$(mktemp)
        jq 'del(.hooks.SessionStart) | if .hooks == {} then del(.hooks) else . end' "$SETTINGS_FILE" > "$tmp" && mv "$tmp" "$SETTINGS_FILE"
    fi

    echo ""
    echo "アンインストール完了！"
}

do_status() {
    echo "SessionStart hook の状態:"
    echo ""

    local target="$HOOKS_DIR/$SCRIPT_NAME"
    if [[ -f "$target" ]]; then
        echo "  スクリプト: $target (インストール済み)"
    else
        echo "  スクリプト: 未インストール"
    fi

    if [[ -f "$SETTINGS_FILE" ]] && jq -e '.hooks.SessionStart' "$SETTINGS_FILE" >/dev/null 2>&1; then
        echo "  settings.json: SessionStart hook 設定あり"
    else
        echo "  settings.json: SessionStart hook 設定なし"
    fi

    echo ""
    echo "Registry:"
    if [[ -d "$REGISTRY_BASE" ]]; then
        local host_count=$(ls -1d "$REGISTRY_BASE"/*/ 2>/dev/null | wc -l)
        echo "  $REGISTRY_BASE ($host_count ホスト)"
        for host_dir in "$REGISTRY_BASE"/*/; do
            [[ -d "$host_dir" ]] || continue
            local host=$(basename "$host_dir")
            local proj_count=$(ls -1d "$host_dir"/*/ 2>/dev/null | wc -l)
            echo "    $host: $proj_count プロジェクト"
        done
    else
        echo "  $REGISTRY_BASE (未作成)"
    fi
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
    --help|-h)
        show_help
        ;;
    "")
        run_hook
        ;;
    *)
        echo "不明なオプション: $1" >&2
        show_help >&2
        exit 1
        ;;
esac
