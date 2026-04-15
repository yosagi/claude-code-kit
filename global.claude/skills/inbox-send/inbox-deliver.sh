#!/bin/bash
# 目的: inbox メッセージを配信する（stdin から本文を読んで inbox に配置）
# 関連: inbox-send.sh（ローカル/リモート両方からこのスクリプトを呼ぶ）
# 前提: 送信先パスとファイル名が確定済みであること
#
# 使い方:
#   cat message.md | inbox-deliver.sh <dest_project_path> <dest_filename>
#
# リモートからの使用:
#   cat message.md | ssh host '~/.claude/skills/inbox-send/inbox-deliver.sh /path/to/project filename.md'

set -euo pipefail

if [[ $# -lt 2 ]]; then
    echo "Usage: inbox-deliver.sh <dest_project_path> <dest_filename>" >&2
    echo "  stdin からメッセージ本文を読み取ります" >&2
    exit 1
fi

DEST_PROJECT="$1"
DEST_FILENAME="$2"

DEST_INBOX="${DEST_PROJECT}/reports/inbox"
DEST_INDEX="${DEST_INBOX}/INDEX.md"

# 0. 送信先プロジェクトの存在確認
if [[ ! -d "$DEST_PROJECT" ]]; then
    echo "Error: destination project not found: $DEST_PROJECT" >&2
    exit 1
fi

# 1. inbox ディレクトリがなければ作成
if [[ ! -d "$DEST_INBOX" ]]; then
    mkdir -p "$DEST_INBOX" "${DEST_INBOX}/done"
    echo "Created: $DEST_INBOX" >&2
fi

# 2. INDEX.md がなければ作成
if [[ ! -f "$DEST_INDEX" ]]; then
    cat > "$DEST_INDEX" << 'INDEXEOF'
# INBOX インデックス

外部プロジェクトからの依頼一覧。詳細は `/inbox read [ファイル名]` で確認する（既読化のため直接読まない）。

INDEXEOF
    echo "Created: $DEST_INDEX" >&2
fi

# 3. stdin から本文を読んでファイルに書き込み
cat > "${DEST_INBOX}/${DEST_FILENAME}"
echo "Created: ${DEST_INBOX}/${DEST_FILENAME}" >&2

# 4. INDEX.md に [NEW] マーカー付きで追記
echo "- [NEW] ${DEST_FILENAME}" >> "$DEST_INDEX"
echo "Updated: $DEST_INDEX" >&2
