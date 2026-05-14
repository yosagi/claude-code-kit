#!/bin/bash
# Claude Code Status Line
# コンテキスト使用率、rate limits、プロジェクト名、cwd、モデルを表示

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

# 色付けヘルパー: colorize <value> （>80: 赤太字, >50: 黄, それ以外: 通常）
colorize() {
    local val=$1
    if [ "$val" -gt 80 ] 2>/dev/null; then
        printf '\033[1;31m%s%%\033[0m' "$val"
    elif [ "$val" -gt 50 ] 2>/dev/null; then
        printf '\033[1;33m%s%%\033[0m' "$val"
    else
        printf '\033[1m%s%%\033[0m' "$val"
    fi
}

# コンテキスト使用率（autocompact buffer 分を加算した実質使用率）
REMAINING=$(echo "$input" | jq -r '.context_window.remaining_percentage // 0' | cut -d. -f1)
WINDOW_SIZE=$(echo "$input" | jq -r '.context_window.context_window_size // 200000')
AUTOCOMPACT_BUFFER=$(( (33000 * 100 + WINDOW_SIZE - 1) / WINDOW_SIZE ))
CTX_USED=$((100 - REMAINING + AUTOCOMPACT_BUFFER))
[ $CTX_USED -gt 100 ] && CTX_USED=100
CTX_FMT="💬 $(colorize "$CTX_USED")"

# rate limits（Pro/Max のみ、フィールドがなければ非表示）
RATE_FMT=""
HAS_RATE=$(echo "$input" | jq -e '.rate_limits' >/dev/null 2>&1 && echo 1 || echo 0)
if [ "$HAS_RATE" = "1" ]; then
    # 5h
    FIVE_USED=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty' | cut -d. -f1)
    FIVE_RESET=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')
    if [ -n "$FIVE_USED" ]; then
        FIVE_FMT=$(colorize "$FIVE_USED")
        if [ -n "$FIVE_RESET" ]; then
            FIVE_TIME=$(date -d "@$FIVE_RESET" '+%-Hh' 2>/dev/null || date -r "$FIVE_RESET" '+%-Hh' 2>/dev/null)
            FIVE_FMT="${FIVE_FMT}@${FIVE_TIME}"
        fi
        RATE_FMT=" 🕐 ${FIVE_FMT}"
    fi
    # 7d
    SEVEN_USED=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty' | cut -d. -f1)
    SEVEN_RESET=$(echo "$input" | jq -r '.rate_limits.seven_day.resets_at // empty')
    if [ -n "$SEVEN_USED" ]; then
        SEVEN_FMT=$(colorize "$SEVEN_USED")
        if [ -n "$SEVEN_RESET" ]; then
            SEVEN_DATE=$(date -d "@$SEVEN_RESET" '+%-m/%-d' 2>/dev/null || date -r "$SEVEN_RESET" '+%-m/%-d' 2>/dev/null)
            SEVEN_FMT="${SEVEN_FMT}@${SEVEN_DATE}"
        fi
        RATE_FMT="${RATE_FMT} ${SEVEN_FMT}"
    fi
fi

# inbox 件数（NEW + 既読）
INBOX_INDEX="$PROJECT_DIR/reports/inbox/INDEX.md"
INBOX_NEW=0
INBOX_READ=0
if [ -f "$INBOX_INDEX" ]; then
    INBOX_NEW=$(grep -c '\[NEW\]' "$INBOX_INDEX" 2>/dev/null)
    INBOX_NEW=${INBOX_NEW:-0}
    INBOX_TOTAL=$(grep -c '^- ' "$INBOX_INDEX" 2>/dev/null)
    INBOX_TOTAL=${INBOX_TOTAL:-0}
    INBOX_READ=$((INBOX_TOTAL - INBOX_NEW))
fi
INBOX_FMT=""
if [ "$INBOX_TOTAL" -gt 0 ] 2>/dev/null; then
    if [ "$INBOX_NEW" -gt 0 ] 2>/dev/null; then
        INBOX_FMT=" | \033[33m📬 ${INBOX_NEW}/${INBOX_TOTAL}\033[0m"
    else
        INBOX_FMT=" | 📬 0/${INBOX_TOTAL}"
    fi
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
    echo -e "[$MODEL] $PROJECT_NAME/$REL_CWD | $CTX_FMT${RATE_FMT}${INBOX_FMT}${ITEMS_FMT}"
else
    echo -e "[$MODEL] $PROJECT_NAME | $CTX_FMT${RATE_FMT}${INBOX_FMT}${ITEMS_FMT}"
fi

# wezterm User Variable を設定（キーマップ制御用）
# /dev/tty 経由で端末にエスケープシーケンスを送る。
# Claude Code 2.1.139+ では statusLine command が制御端末なし (tty_nr=0) で
# 起動されるため /dev/tty が実際の端末に繋がらない。
# フォールバックとして親プロセスチェーンから実際の pty デバイスを探す。
find_tty_device() {
    # /dev/tty が使えるか確認（制御端末がある場合）
    local tty_nr
    tty_nr=$(awk '{print $7}' /proc/self/stat 2>/dev/null)
    if [ "${tty_nr:-0}" -ne 0 ] 2>/dev/null; then
        echo "/dev/tty"
        return 0
    fi
    # 制御端末がない場合、親プロセスチェーンから pty を探す
    local pid=$$
    while [ "$pid" -gt 1 ]; do
        pid=$(awk '{print $4}' /proc/$pid/stat 2>/dev/null) || break
        local fd
        for fd in /proc/$pid/fd/0 /proc/$pid/fd/1 /proc/$pid/fd/2; do
            local target
            target=$(readlink "$fd" 2>/dev/null) || continue
            if [[ "$target" == /dev/pts/* ]]; then
                echo "$target"
                return 0
            fi
        done
    done
    return 1
}

TTY_DEV=$(find_tty_device)
if [ -n "$TTY_DEV" ] && [ -c "$TTY_DEV" ]; then
    printf '\033]1337;SetUserVar=%s=%s\007' 'WEZTERM_AI_HELPER' "$(printf '%s' 'claude-code' | base64)" > "$TTY_DEV"
fi
