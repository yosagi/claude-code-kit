# statusline 部品: IDEAS / TODO 件数
# 枠組み statusline.sh から source される。SL_* 変数を読み、断片を stdout に出す

seg_items() {
    local ideas=0 todos=0
    local ideas_index="$SL_PROJECT_DIR/reports/ideas/INDEX.md"
    local todos_index="$SL_PROJECT_DIR/reports/todos/INDEX.md"
    [ -f "$ideas_index" ] && ideas=$(grep -c '^- [0-9]\{4\}-' "$ideas_index" 2>/dev/null)
    [ -f "$todos_index" ] && todos=$(grep -c '^- [0-9]\{4\}-' "$todos_index" 2>/dev/null)
    ideas=${ideas:-0}
    todos=${todos:-0}
    if [ "$ideas" -gt 0 ] 2>/dev/null || [ "$todos" -gt 0 ] 2>/dev/null; then
        printf '💡%s 📋%s' "$ideas" "$todos"
    fi
}
