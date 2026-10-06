#!/bin/bash
# 目的: inbox の受信依頼を操作する（既読化・完了処理）
# 関連: inbox SKILL.md
# 前提: -C でプロジェクトルートを渡す（省略時は cwd。cwd に reports/inbox が無ければ親を 5 階層まで遡る）

set -e

usage() {
    cat << 'EOF'
Usage:
  inbox-read.sh [-C <project_root>] read <filename>
  inbox-read.sh [-C <project_root>] done <filename>

Options:
  -C <project_root>  - 処理前にこのディレクトリへ移動する（`cd && script` と連結しないための口）

Commands:
  read  - [NEW] マーカー削除 + 内容表示
  done  - done/ に移動 + INDEX から削除

Examples:
  inbox-read.sh -C ~/work/myproject read 2026-01-25_from_claude_request.md
  inbox-read.sh -C ~/work/myproject done 2026-01-25_from_claude_request.md
EOF
    exit 1
}

PROJECT_ROOT=""
if [ "${1:-}" = "-C" ]; then
    if [ $# -lt 2 ]; then
        usage
    fi
    PROJECT_ROOT="$2"
    shift 2
fi

if [ $# -lt 2 ]; then
    usage
fi

if [ -n "$PROJECT_ROOT" ]; then
    if ! cd "$PROJECT_ROOT" 2>/dev/null; then
        echo "Error: cannot cd to project root: $PROJECT_ROOT"
        exit 1
    fi
elif [ ! -d "reports/inbox" ]; then
    # サブディレクトリからの実行対策: 親ディレクトリを遡って reports/inbox を探す
    search_dir="."
    for _ in 1 2 3 4 5; do
        search_dir="$search_dir/.."
        if [ -d "$search_dir/reports/inbox" ]; then
            cd "$search_dir"
            echo "Note: project root resolved to $(pwd)"
            break
        fi
    done
fi

COMMAND="$1"
FILENAME="$2"
INBOX_DIR="reports/inbox"
INDEX_FILE="${INBOX_DIR}/INDEX.md"
FILE_PATH="${INBOX_DIR}/${FILENAME}"

case "$COMMAND" in
    read)
        # ファイル存在チェック
        if [ ! -f "$FILE_PATH" ]; then
            echo "Error: File not found: $FILE_PATH"
            exit 1
        fi

        # INDEX.md の [NEW] マーカーを削除
        if [ -f "$INDEX_FILE" ]; then
            sed -i "s/- \[NEW\] ${FILENAME}/- ${FILENAME}/" "$INDEX_FILE"
            echo "Marked as read in INDEX.md"
        fi

        # 内容を表示
        echo ""
        echo "=== Content of ${FILENAME} ==="
        echo ""
        cat "$FILE_PATH"
        ;;

    done)
        DONE_DIR="${INBOX_DIR}/done"

        # ファイル存在チェック
        if [ ! -f "$FILE_PATH" ]; then
            echo "Error: File not found: $FILE_PATH"
            exit 1
        fi

        # done/ ディレクトリがなければ作成
        if [ ! -d "$DONE_DIR" ]; then
            mkdir -p "$DONE_DIR"
        fi

        # 1. done/ に移動
        mv "$FILE_PATH" "${DONE_DIR}/${FILENAME}"
        echo "Moved to: ${DONE_DIR}/${FILENAME}"

        # 2. INDEX.md から該当行を削除
        if [ -f "$INDEX_FILE" ]; then
            sed -i "/- \[NEW\] ${FILENAME}/d" "$INDEX_FILE"
            sed -i "/- ${FILENAME}/d" "$INDEX_FILE"
            echo "Removed from INDEX.md"
        fi

        echo ""
        echo "=== Done ==="
        echo "File: ${FILENAME}"
        ;;

    *)
        echo "Error: Unknown command: $COMMAND"
        usage
        ;;
esac
