# statusline 部品: inbox 件数（NEW / 合計）
# 枠組み statusline.sh から source される。SL_* 変数を読み、断片を stdout に出す

seg_inbox() {
    local index="$SL_PROJECT_DIR/reports/inbox/INDEX.md"
    [ -f "$index" ] || return 0
    local new total
    new=$(grep -c '\[NEW\]' "$index" 2>/dev/null)
    total=$(grep -c '^- ' "$index" 2>/dev/null)
    [ "${total:-0}" -gt 0 ] 2>/dev/null || return 0
    if [ "${new:-0}" -gt 0 ] 2>/dev/null; then
        printf '\033[33m📬 %s/%s\033[0m' "$new" "$total"
    else
        printf '📬 0/%s' "$total"
    fi
}
