#!/bin/bash
# 目的: inbox 依頼を送信する（draft ファイルを送信先に配送）
# 関連: inbox-send SKILL.md, inbox-deliver.sh
# 前提: 送信先パスが特定済み、draft ファイルが作成済みであること

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

usage() {
    cat << 'EOF'
Usage:
  inbox-send.sh <dest_project_path> <draft_file_path> <source_project_name> <date>

Arguments:
  dest_project_path    - 送信先プロジェクトのパス（例: ~/work/myproject）
                         リモートの場合: remote:hostname:/path/to/project
  draft_file_path      - draft ファイルのパス（例: reports/inbox/draft/to_xxx_topic.md）
  source_project_name  - 送信元プロジェクト名（例: claude）
  date                 - 日付（例: 2026-02-19）

Example:
  inbox-send.sh ~/work/myproject reports/inbox/draft/to_xxx_topic.md myproject 2026-01-25
  inbox-send.sh remote:pc-b:~/work/wip reports/inbox/draft/to_wip_topic.md claude 2026-03-31
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

# draft ファイルの存在確認（サブディレクトリからの実行対策）
if [ ! -f "$DRAFT_FILE" ]; then
    # 相対パスの場合、親ディレクトリを遡って探す
    found=""
    search_dir="."
    for _ in 1 2 3 4 5; do
        search_dir="$search_dir/.."
        if [ -f "$search_dir/$DRAFT_FILE" ]; then
            found="$search_dir/$DRAFT_FILE"
            break
        fi
    done
    if [ -n "$found" ]; then
        DRAFT_FILE=$(realpath "$found")
        echo "Note: draft file found at $DRAFT_FILE"
    else
        echo "Error: draft file not found: $2"
        exit 1
    fi
fi

# draft ファイル名から topic を抽出
DRAFT_BASENAME=$(basename "$DRAFT_FILE")
TOPIC=$(echo "$DRAFT_BASENAME" | sed 's/^to_[^_]*_//' | sed 's/\.md$//')

# 送信先ファイル名を生成
DEST_FILENAME="${DATE}_from_${SOURCE_PROJECT}_${TOPIC}.md"

# 本文を準備（「送信先:」行を除去）
prepare_content() {
    grep -v '^送信先:' "$DRAFT_FILE" | sed '1{/^$/d}'
}

if [[ "$DEST_PROJECT" == remote:* ]]; then
    # --- リモート送信 ---
    HOST=$(echo "$DEST_PROJECT" | cut -d: -f2)
    REMOTE_PATH=$(echo "$DEST_PROJECT" | cut -d: -f3-)

    echo "Sending to remote: $HOST:$REMOTE_PATH"

    # リモート側の inbox-deliver.sh を使って配信
    REMOTE_DELIVER="~/.claude/skills/inbox-send/inbox-deliver.sh"
    prepare_content | ssh "$HOST" "$REMOTE_DELIVER" "'$REMOTE_PATH'" "'$DEST_FILENAME'"

    # draft ファイルを削除
    rm "$DRAFT_FILE"
    echo "Removed: $DRAFT_FILE"
else
    # --- ローカル送信 ---
    # パスを正規化: /reports/inbox が含まれていたらプロジェクトルートに戻す
    DEST_PROJECT=$(echo "$DEST_PROJECT" | sed 's|/reports/inbox/*$||' | sed 's|/reports/*$||')

    # inbox-deliver.sh を使って配信
    prepare_content | "$SCRIPT_DIR/inbox-deliver.sh" "$DEST_PROJECT" "$DEST_FILENAME"

    # draft ファイルを削除
    rm "$DRAFT_FILE"
    echo "Removed: $DRAFT_FILE"
fi

# 結果サマリ
echo ""
echo "=== Delivery Complete ==="
echo "From: $SOURCE_PROJECT"
echo "To: $DEST_PROJECT"
echo "File: $DEST_FILENAME"
