#!/bin/bash
# 目的: Claude Code のグローバル設定に記憶ファイルへのアクセス許可を追加
# 関連: reports/todos/2025-12-21_mid_setup_permissions.md
# 前提: jq がインストールされていること

set -e

SETTINGS_FILE="$HOME/.claude/settings.json"

# 追加する許可（相対パス、cwd がプロジェクトルートにある前提）
PERMISSIONS=(
    'Read(reports/memory/**)'
    'Read(reports/personas/**)'
    'Read(reports/next_session.md)'
    'Read(reports/ideas/**)'
    'Read(reports/todos/**)'
    'Edit(reports/memory/**)'
    'Edit(reports/personas/**)'
    'Edit(reports/next_session.md)'
    'Edit(reports/ideas/**)'
    'Edit(reports/todos/**)'
    'Write(reports/memory/**)'
    'Write(reports/personas/**)'
    'Write(reports/next_session.md)'
    'Write(reports/ideas/**)'
    'Write(reports/todos/**)'
)

# jq がインストールされているか確認
if ! command -v jq &> /dev/null; then
    echo "Error: jq is required but not installed." >&2
    exit 1
fi

# 設定ファイルが存在しない場合は作成
if [[ ! -f "$SETTINGS_FILE" ]]; then
    echo "Creating $SETTINGS_FILE"
    mkdir -p "$(dirname "$SETTINGS_FILE")"
    echo '{}' > "$SETTINGS_FILE"
fi

# 現在の設定を読み込み
current=$(cat "$SETTINGS_FILE")

# permissions.allow 配列を構築
permissions_json=$(printf '%s\n' "${PERMISSIONS[@]}" | jq -R . | jq -s .)

# 既存の permissions.allow とマージ（重複を除去）
updated=$(echo "$current" | jq --argjson new_perms "$permissions_json" '
    .permissions.allow = ((.permissions.allow // []) + $new_perms | unique)
')

# 書き込み
echo "$updated" > "$SETTINGS_FILE"

echo "Updated $SETTINGS_FILE"
echo "Added permissions:"
printf '  - %s\n' "${PERMISSIONS[@]}"
echo ""
echo "Note: Restart Claude Code session for changes to take effect."
