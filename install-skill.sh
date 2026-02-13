#!/bin/bash
# スキルインストーラー
# Usage: install-skill.sh <skill-dir>
#
# 1. 指定したスキルを ~/.claude/skills/ にコピー
# 2. *.sh があれば settings.json の excludedCommands に追加

set -euo pipefail

SKILL_SOURCE="$1"
SKILL_NAME=$(basename "$SKILL_SOURCE")
DEST_DIR="$HOME/.claude/skills/$SKILL_NAME"
SETTINGS_FILE="$HOME/.claude/settings.json"

# 引数チェック
if [[ -z "$SKILL_SOURCE" ]]; then
    echo "Usage: $0 <skill-dir>" >&2
    exit 1
fi

if [[ ! -d "$SKILL_SOURCE" ]]; then
    echo "Error: Skill directory not found: $SKILL_SOURCE" >&2
    exit 1
fi

# jq が必要
if ! command -v jq &> /dev/null; then
    echo "Error: jq is required but not installed" >&2
    exit 1
fi

echo "Installing skill: $SKILL_NAME"

# 1. スキルをコピー
mkdir -p "$HOME/.claude/skills"
if [[ -d "$DEST_DIR" ]]; then
    echo "  Updating existing skill..."
    rm -rf "$DEST_DIR"
fi
cp -r "$SKILL_SOURCE" "$DEST_DIR"
echo "  Copied to: $DEST_DIR"

# 2. 実行可能スクリプト（*.sh, *.py）を探して excludedCommands に追加
SCRIPTS_FOUND=()
for script in "$DEST_DIR"/*.sh "$DEST_DIR"/*.py; do
    if [[ -f "$script" ]]; then
        chmod +x "$script"
        SCRIPTS_FOUND+=("$script")
    fi
done

if [[ ${#SCRIPTS_FOUND[@]} -eq 0 ]]; then
    echo "  No shell scripts found (nothing to add to sandbox exceptions)"
    exit 0
fi

# settings.json がなければ作成
if [[ ! -f "$SETTINGS_FILE" ]]; then
    echo '{}' > "$SETTINGS_FILE"
fi

# 各スクリプトを excludedCommands に追加
for script in "${SCRIPTS_FOUND[@]}"; do
    # ~ 表記に変換（settings.json での表記に合わせる）
    SCRIPT_PATH="~/.claude/skills/$SKILL_NAME/$(basename "$script"):*"

    # 既に登録されているかチェック
    if jq -e ".sandbox.excludedCommands // [] | index(\"$SCRIPT_PATH\")" "$SETTINGS_FILE" > /dev/null 2>&1; then
        echo "  Already registered: $SCRIPT_PATH"
        continue
    fi

    # excludedCommands に追加
    TEMP_FILE=$(mktemp)
    jq --arg cmd "$SCRIPT_PATH" '
        .sandbox.excludedCommands = ((.sandbox.excludedCommands // []) + [$cmd] | unique)
    ' "$SETTINGS_FILE" > "$TEMP_FILE"
    mv "$TEMP_FILE" "$SETTINGS_FILE"

    echo "  Added to excludedCommands: $SCRIPT_PATH"
done

echo "Done!"
