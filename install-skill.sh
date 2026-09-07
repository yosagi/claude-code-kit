#!/bin/bash
# スキルインストーラー
# Usage: install-skill.sh <skill-dir>
#        install-skill.sh --uninstall <skill-name>
#
# インストール:
#   1. 指定したスキルを ~/.claude/skills/ にコピー
#   2. *.sh があれば settings.json の excludedCommands に追加
#
# アンインストール:
#   1. ~/.claude/skills/<name>/ を削除
#   2. そのスキルが登録した excludedCommands のエントリを除去

set -euo pipefail

SETTINGS_FILE="$HOME/.claude/settings.json"
SKILLS_ROOT="$HOME/.claude/skills"

usage() {
    echo "Usage: $0 <skill-dir>" >&2
    echo "       $0 --uninstall <skill-name>" >&2
}

# jq が必要（両モード共通）
if ! command -v jq &> /dev/null; then
    echo "Error: jq is required but not installed" >&2
    exit 1
fi

# excludedCommands から指定スキルのエントリを除去する
remove_excluded_commands() {
    local skill_name="$1"
    local prefix="~/.claude/skills/$skill_name/"

    [[ -f "$SETTINGS_FILE" ]] || return 0

    local removed
    removed=$(jq -r --arg p "$prefix" '
        [(.sandbox.excludedCommands // [])[] | select(startswith($p))] | length
    ' "$SETTINGS_FILE")

    if [[ "$removed" -eq 0 ]]; then
        return 0
    fi

    local temp_file
    temp_file=$(mktemp)
    jq --arg p "$prefix" '
        .sandbox.excludedCommands = [(.sandbox.excludedCommands // [])[] | select(startswith($p) | not)]
    ' "$SETTINGS_FILE" > "$temp_file"
    mv "$temp_file" "$SETTINGS_FILE"

    echo "  Removed from excludedCommands: $removed entries"
}

# --uninstall モード
if [[ "${1:-}" == "--uninstall" ]]; then
    SKILL_NAME="${2:-}"
    if [[ -z "$SKILL_NAME" ]]; then
        usage
        exit 1
    fi
    # パス区切りを含む名前は受け付けない（誤爆防止）
    if [[ "$SKILL_NAME" == */* || "$SKILL_NAME" == "." || "$SKILL_NAME" == ".." ]]; then
        echo "Error: invalid skill name: $SKILL_NAME" >&2
        exit 1
    fi

    TARGET_DIR="$SKILLS_ROOT/$SKILL_NAME"
    if [[ ! -d "$TARGET_DIR" ]]; then
        # 既に無い場合も excludedCommands の残骸だけ掃除して正常終了
        remove_excluded_commands "$SKILL_NAME"
        exit 0
    fi

    echo "Uninstalling skill: $SKILL_NAME"
    rm -rf "$TARGET_DIR"
    echo "  Removed: $TARGET_DIR"
    remove_excluded_commands "$SKILL_NAME"
    echo "Done!"
    exit 0
fi

SKILL_SOURCE="${1:-}"
SKILL_NAME=$(basename "$SKILL_SOURCE")
DEST_DIR="$SKILLS_ROOT/$SKILL_NAME"

# 引数チェック
if [[ -z "$SKILL_SOURCE" ]]; then
    usage
    exit 1
fi

if [[ ! -d "$SKILL_SOURCE" ]]; then
    echo "Error: Skill directory not found: $SKILL_SOURCE" >&2
    exit 1
fi

echo "Installing skill: $SKILL_NAME"

# 1. スキルをコピー
mkdir -p "$SKILLS_ROOT"
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
