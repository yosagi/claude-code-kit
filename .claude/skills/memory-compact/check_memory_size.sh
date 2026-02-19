#!/bin/bash
# PostToolUse hook: 記憶ファイルのサイズチェック
# Skill 使用後に発火し、上限超過時に memory-compact を促す

LIMIT_DIARY=30
LIMIT_HISTORY=25

# stdin から hook 入力を読む
INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty')

# プロジェクトルート取得（CLAUDE_PROJECT_DIR 優先、ccexport フォールバック）
PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-}"
if [[ -z "$PROJECT_ROOT" ]] && [[ -n "$SESSION_ID" ]]; then
    PROJECT_ROOT=$(ccexport session-info -s "$SESSION_ID" --json 2>/dev/null | jq -r '.project // empty')
fi
if [[ -z "$PROJECT_ROOT" ]]; then
    exit 0
fi

# "- YYYY-MM-DD:" パターンのエントリ数をカウント
count_entries() {
    local file="$1"
    if [[ -f "$file" ]]; then
        grep -c '^- [0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}:' "$file" 2>/dev/null || true
    else
        echo 0
    fi
}

exceeded=()

# 日記ファイルのチェック（archive を除く）
for diary in "$PROJECT_ROOT"/reports/personas/*.md; do
    if [[ -f "$diary" ]] && [[ "$(basename "$diary")" != *_archive.md ]]; then
        count=$(count_entries "$diary")
        if (( count > LIMIT_DIARY )); then
            name=$(basename "$diary")
            exceeded+=("$name: ${count}件/${LIMIT_DIARY}件")
        fi
    fi
done

# work_history のチェック
history_file="$PROJECT_ROOT/reports/memory/work_history.md"
if [[ -f "$history_file" ]]; then
    count=$(count_entries "$history_file")
    if (( count > LIMIT_HISTORY )); then
        exceeded+=("work_history.md: ${count}件/${LIMIT_HISTORY}件")
    fi
fi

# 超過があれば通知
if (( ${#exceeded[@]} > 0 )); then
    echo ""
    echo "---"
    echo "記憶ファイルが上限を超えています:"
    for item in "${exceeded[@]}"; do
        echo "  - $item"
    done
    echo "/memory-compact を実行して古いエントリを要約・圧縮してください。"
    echo "---"
fi
