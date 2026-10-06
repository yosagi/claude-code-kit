# statusline 部品: コンテキスト使用率と rate limits（5h / 7d）
# 枠組み statusline.sh から source される。SL_* 変数と colorize を使い、断片を stdout に出す

seg_usage() {
    # コンテキスト使用率（autocompact buffer 分を加算した実質使用率）
    local window=${SL_CTX_WINDOW:-200000}
    [ "$window" -gt 0 ] 2>/dev/null || window=200000
    local buffer=$(( (33000 * 100 + window - 1) / window ))
    local used=$(( 100 - ${SL_CTX_REMAINING:-0} + buffer ))
    [ "$used" -gt 100 ] && used=100
    local out="💬 $(colorize "$used")"

    # rate limits（Pro/Max のみ、フィールドがなければ非表示）
    if [ "$SL_HAS_RATE" = "1" ]; then
        local fmt t
        if [ -n "$SL_FIVE_USED" ]; then
            fmt=$(colorize "$SL_FIVE_USED")
            if [ -n "$SL_FIVE_RESET" ]; then
                t=$(date -d "@$SL_FIVE_RESET" '+%-Hh' 2>/dev/null || date -r "$SL_FIVE_RESET" '+%-Hh' 2>/dev/null)
                fmt="${fmt}@${t}"
            fi
            out="${out} 🕐 ${fmt}"
        fi
        if [ -n "$SL_SEVEN_USED" ]; then
            fmt=$(colorize "$SL_SEVEN_USED")
            if [ -n "$SL_SEVEN_RESET" ]; then
                t=$(date -d "@$SL_SEVEN_RESET" '+%-m/%-d' 2>/dev/null || date -r "$SL_SEVEN_RESET" '+%-m/%-d' 2>/dev/null)
                fmt="${fmt}@${t}"
            fi
            out="${out} ${fmt}"
        fi
    fi
    printf '%s' "$out"
}
