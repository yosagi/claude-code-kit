#!/bin/bash
# Claude Code Status Line
# コンテキスト残量、プロジェクト名、cwd、モデルを表示

input=$(cat)

# 基本情報を取得
MODEL=$(echo "$input" | jq -r '.model.display_name // "?"')
PROJECT_DIR=$(echo "$input" | jq -r '.workspace.project_dir // "?"')
CURRENT_DIR=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // "?"')
PROJECT_NAME=$(basename "$PROJECT_DIR")

# プロジェクトルート相対の cwd を計算
if [ "$CURRENT_DIR" = "$PROJECT_DIR" ]; then
    REL_CWD=""
else
    # project_dir を prefix として削除
    REL_CWD="${CURRENT_DIR#$PROJECT_DIR/}"
    if [ "$REL_CWD" = "$CURRENT_DIR" ]; then
        # project_dir 外にいる場合はフルパス表示
        REL_CWD="$CURRENT_DIR"
    fi
fi

# コンテキスト情報
PERCENT_USED=$(echo "$input" | jq -r '.context_window.used_percentage // 0' | cut -d. -f1)
REMAINING=$(echo "$input" | jq -r '.context_window.remaining_percentage // 0' | cut -d. -f1)

# autocompact buffer (16.5%) を差し引いた実質残量
AUTOCOMPACT_BUFFER=17
LEFT=$((REMAINING - AUTOCOMPACT_BUFFER))
[ $LEFT -lt 0 ] && LEFT=0

# 残量に応じた色付け
# 黄色: \033[33m, 太字赤: \033[1;31m, リセット: \033[0m
if [ $LEFT -le 10 ]; then
    LEFT_FMT="\033[1;31m${LEFT}%\033[0m"
elif [ $LEFT -le 20 ]; then
    LEFT_FMT="\033[33m${LEFT}%\033[0m"
else
    LEFT_FMT="${LEFT}%"
fi

# コスト（小数点以下2桁）
COST=$(echo "$input" | jq -r '.cost.total_cost_usd // 0')
COST_FMT=$(printf "%.2f" "$COST")

# inbox NEW 件数
INBOX_INDEX="$PROJECT_DIR/reports/inbox/INDEX.md"
INBOX_NEW=0
if [ -f "$INBOX_INDEX" ]; then
    INBOX_NEW=$(grep -c '\[NEW\]' "$INBOX_INDEX" 2>/dev/null)
    INBOX_NEW=${INBOX_NEW:-0}
fi
INBOX_FMT=""
if [ "$INBOX_NEW" -gt 0 ] 2>/dev/null; then
    INBOX_FMT=" | \033[33m📬 ${INBOX_NEW}\033[0m"
fi

# IDEAS / TODO 件数
IDEAS_INDEX="$PROJECT_DIR/reports/ideas/INDEX.md"
TODOS_INDEX="$PROJECT_DIR/reports/todos/INDEX.md"
IDEAS_COUNT=0
TODOS_COUNT=0
if [ -f "$IDEAS_INDEX" ]; then
    IDEAS_COUNT=$(grep -c '^- [0-9]\{4\}-' "$IDEAS_INDEX" 2>/dev/null)
    IDEAS_COUNT=${IDEAS_COUNT:-0}
fi
if [ -f "$TODOS_INDEX" ]; then
    TODOS_COUNT=$(grep -c '^- [0-9]\{4\}-' "$TODOS_INDEX" 2>/dev/null)
    TODOS_COUNT=${TODOS_COUNT:-0}
fi
ITEMS_FMT=""
if [ "$IDEAS_COUNT" -gt 0 ] 2>/dev/null || [ "$TODOS_COUNT" -gt 0 ] 2>/dev/null; then
    ITEMS_FMT=" | 💡${IDEAS_COUNT} 📋${TODOS_COUNT}"
fi

# 出力（cwd があれば表示）
if [ -n "$REL_CWD" ]; then
    echo -e "[$MODEL] $PROJECT_NAME/$REL_CWD | Context: ${PERCENT_USED}% (Left: $LEFT_FMT) | \$${COST_FMT}${INBOX_FMT}${ITEMS_FMT}"
else
    echo -e "[$MODEL] $PROJECT_NAME | Context: ${PERCENT_USED}% (Left: $LEFT_FMT) | \$${COST_FMT}${INBOX_FMT}${ITEMS_FMT}"
fi

# wezterm User Variable を設定（キーマップ制御用）
# /dev/tty に直接送ることで Claude Code のフィルタリングを回避
if [ -c /dev/tty ]; then
    printf '\033]1337;SetUserVar=%s=%s\007' 'WEZTERM_AI_HELPER' "$(printf '%s' 'claude-code' | base64)" > /dev/tty
fi
