#!/bin/bash
# 目的: inbox 操作（send / read / done）を一括で扱う
# 関連: inbox SKILL.md
# 前提: 送信の場合は送信先パスが特定済みであること

set -e

usage() {
    cat << 'EOF'
Usage:
  inbox.sh send <dest_project_path> <draft_file_path> <source_project_name> <date>
  inbox.sh read <filename>
  inbox.sh done <filename>

Commands:
  send  - 配送 + [NEW] マーカー付き INDEX 追記
  read  - [NEW] マーカー削除 + 内容表示
  done  - done/ に移動 + INDEX から削除

Examples:
  inbox.sh send ~/work/myproject reports/inbox/draft/to_xxx_topic.md myproject 2026-01-25
  inbox.sh read 2026-01-25_from_claude_request.md
  inbox.sh done 2026-01-25_from_claude_request.md
EOF
    exit 1
}

# 引数チェック
if [ $# -lt 1 ]; then
    usage
fi

COMMAND="$1"
shift

case "$COMMAND" in
    send)
        if [ $# -lt 4 ]; then
            echo "Error: send requires 4 arguments"
            usage
        fi

        DEST_PROJECT="$1"
        DRAFT_FILE="$2"
        SOURCE_PROJECT="$3"
        DATE="$4"

        # パスを正規化: /reports/inbox が含まれていたらプロジェクトルートに戻す
        DEST_PROJECT=$(echo "$DEST_PROJECT" | sed 's|/reports/inbox/*$||' | sed 's|/reports/*$||')

        # 送信先 inbox ディレクトリ
        DEST_INBOX="${DEST_PROJECT}/reports/inbox"
        DEST_INDEX="${DEST_INBOX}/INDEX.md"

        # draft ファイル名から topic を抽出
        DRAFT_BASENAME=$(basename "$DRAFT_FILE")
        TOPIC=$(echo "$DRAFT_BASENAME" | sed 's/^to_[^_]*_//' | sed 's/\.md$//')

        # 送信先ファイル名を生成
        DEST_FILENAME="${DATE}_from_${SOURCE_PROJECT}_${TOPIC}.md"
        DEST_FILE="${DEST_INBOX}/${DEST_FILENAME}"

        # 1. 送信先 inbox/ がなければ作成
        if [ ! -d "$DEST_INBOX" ]; then
            mkdir -p "$DEST_INBOX"
            mkdir -p "${DEST_INBOX}/done"
            echo "Created: $DEST_INBOX"
        fi

        # 2. INDEX.md がなければ作成
        if [ ! -f "$DEST_INDEX" ]; then
            cat > "$DEST_INDEX" << 'INDEXEOF'
# INBOX インデックス

外部プロジェクトからの依頼一覧。詳細は `/inbox read [ファイル名]` で確認する（既読化のため直接読まない）。

INDEXEOF
            echo "Created: $DEST_INDEX"
        fi

        # 3. draft ファイルから「送信先: xxx」行を除去してコピー
        grep -v '^送信先:' "$DRAFT_FILE" | sed '1{/^$/d}' > "$DEST_FILE"
        echo "Created: $DEST_FILE"

        # 4. INDEX.md に [NEW] マーカー付きでファイル名を追記
        echo "- [NEW] ${DEST_FILENAME}" >> "$DEST_INDEX"
        echo "Updated: $DEST_INDEX"

        # 5. draft ファイルを削除
        rm "$DRAFT_FILE"
        echo "Removed: $DRAFT_FILE"

        # 6. 結果サマリ
        echo ""
        echo "=== Delivery Complete ==="
        echo "From: $SOURCE_PROJECT"
        echo "To: $DEST_PROJECT"
        echo "File: $DEST_FILENAME"
        ;;

    read)
        if [ $# -lt 1 ]; then
            echo "Error: read requires filename"
            usage
        fi

        FILENAME="$1"
        INBOX_DIR="reports/inbox"
        INDEX_FILE="${INBOX_DIR}/INDEX.md"
        FILE_PATH="${INBOX_DIR}/${FILENAME}"

        # ファイル存在チェック
        if [ ! -f "$FILE_PATH" ]; then
            echo "Error: File not found: $FILE_PATH"
            exit 1
        fi

        # INDEX.md の [NEW] マーカーを削除
        if [ -f "$INDEX_FILE" ]; then
            # [NEW] を削除（該当行のみ）
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
        if [ $# -lt 1 ]; then
            echo "Error: done requires filename"
            usage
        fi

        FILENAME="$1"
        INBOX_DIR="reports/inbox"
        INDEX_FILE="${INBOX_DIR}/INDEX.md"
        FILE_PATH="${INBOX_DIR}/${FILENAME}"
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
            # [NEW] あり/なし両方に対応
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
