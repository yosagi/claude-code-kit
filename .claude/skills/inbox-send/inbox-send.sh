#!/bin/bash
# 目的: inbox 依頼を送信する（draft ファイルを送信先に配送）
# 関連: inbox-send SKILL.md
# 前提: 送信先パスが特定済み、draft ファイルが作成済みであること

set -e

usage() {
    cat << 'EOF'
Usage:
  inbox-send.sh <dest_project_path> <draft_file_path> <source_project_name> <date>

Arguments:
  dest_project_path    - 送信先プロジェクトのパス（例: ~/work/myproject）
  draft_file_path      - draft ファイルのパス（例: reports/inbox/draft/to_xxx_topic.md）
  source_project_name  - 送信元プロジェクト名（例: claude）
  date                 - 日付（例: 2026-02-19）

Example:
  inbox-send.sh ~/work/myproject reports/inbox/draft/to_xxx_topic.md myproject 2026-01-25
EOF
    exit 1
}

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
