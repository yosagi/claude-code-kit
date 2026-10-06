# statusline 部品: モデル名とプロジェクト名（プロジェクトルート相対の cwd）
# 枠組み statusline.sh から source される。SL_* 変数を読み、断片を stdout に出す

seg_location() {
    local project_name rel_cwd
    project_name=$(basename "$SL_PROJECT_DIR")

    if [ "$SL_CURRENT_DIR" = "$SL_PROJECT_DIR" ]; then
        rel_cwd=""
    else
        rel_cwd="${SL_CURRENT_DIR#"$SL_PROJECT_DIR"/}"
        # project_dir 外にいる場合はフルパス表示
        [ "$rel_cwd" = "$SL_CURRENT_DIR" ] && rel_cwd="$SL_CURRENT_DIR"
    fi

    if [ -n "$rel_cwd" ]; then
        printf '[%s] %s/%s' "$SL_MODEL" "$project_name" "$rel_cwd"
    else
        printf '[%s] %s' "$SL_MODEL" "$project_name"
    fi
}
