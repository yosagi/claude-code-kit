#!/bin/bash
# 目的: inbox の受信依頼を操作する（既読化・完了処理）
# 関連: inbox SKILL.md
# 前提: プロジェクトルートで実行すること

set -e

usage() {
    cat << 'EOF'
Usage:
  inbox-read.sh read <filename>
  inbox-read.sh done <filename>

Commands:
  read  - [NEW] マーカー削除 + 内容表示
  done  - done/ に移動 + INDEX から削除

Examples:
  inbox-read.sh read 2026-01-25_from_claude_request.md
  inbox-read.sh done 2026-01-25_from_claude_request.md
EOF
    exit 1
}

if [ $# -lt 2 ]; then
    usage
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
