#!/bin/bash
# Claude Code Status Line（枠組み）
#
# 表示の中身は部品が作り、この枠組みは入力 JSON を配って断片をつなぐだけ。
#
#   ~/.claude/statusline.d/
#   ├── kit/        キット同梱の部品。NN-name.sh を source して seg_<name> を呼ぶ（setup_global.sh が管理）
#   ├── segments/   外部の表示部品。実行ファイル。同期実行、stdin に JSON、stdout の 1 行目が断片
#   └── sinks/      外部の吸い出し部品。実行ファイル。切り離して実行、stdin に JSON、出力は捨てる
#
# kit/ と segments/ はファイル名でまとめて並べる（NN 接頭辞で順序が決まる）。断片は " | " でつなぐ。
# segments/ は SEGMENT_TIMEOUT で打ち切り、非 0 終了か出力が空ならその断片を落とす。
# sinks/ は setsid で切り離すので、親プロセスをたどる処理（端末の特定など）は動かない。端末を触るものは segments/ に置く。

input=$(cat)

STATUSLINE_D="${CLAUDE_STATUSLINE_D:-$HOME/.claude/statusline.d}"
SEGMENT_TIMEOUT="${CLAUDE_STATUSLINE_SEGMENT_TIMEOUT:-0.3}"

# sinks は最初に放つ（本体の描画を待たせない）
if [ -d "$STATUSLINE_D/sinks" ]; then
    for f in "$STATUSLINE_D/sinks"/*; do
        [ -f "$f" ] && [ -x "$f" ] || continue
        printf '%s' "$input" | setsid -f "$f" >/dev/null 2>&1
    done
fi

# 入力 JSON の解析は一回だけ。キット部品はこの SL_* 変数を読む
eval "$(printf '%s' "$input" | jq -r '
    def num: if . == null then "" else (. | floor | tostring) end;
    @sh "SL_MODEL=\(.model.display_name // "?")",
    @sh "SL_PROJECT_DIR=\(.workspace.project_dir // "?")",
    @sh "SL_CURRENT_DIR=\(.workspace.current_dir // .cwd // "?")",
    @sh "SL_CTX_REMAINING=\(.context_window.remaining_percentage // 0 | num)",
    @sh "SL_CTX_WINDOW=\(.context_window.context_window_size // 200000 | num)",
    @sh "SL_HAS_RATE=\(if .rate_limits then "1" else "0" end)",
    @sh "SL_FIVE_USED=\(.rate_limits.five_hour.used_percentage | num)",
    @sh "SL_FIVE_RESET=\(.rate_limits.five_hour.resets_at // "")",
    @sh "SL_SEVEN_USED=\(.rate_limits.seven_day.used_percentage | num)",
    @sh "SL_SEVEN_RESET=\(.rate_limits.seven_day.resets_at // "")"
' 2>/dev/null)"

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

# 部品の一覧（"basename<TAB>種別<TAB>パス"）をファイル名順に並べる
list_parts() {
    local f
    for f in "$STATUSLINE_D/kit"/*.sh; do
        [ -f "$f" ] && printf '%s\tkit\t%s\n' "$(basename "$f")" "$f"
    done
    for f in "$STATUSLINE_D/segments"/*; do
        [ -f "$f" ] && [ -x "$f" ] && printf '%s\tseg\t%s\n' "$(basename "$f")" "$f"
    done
}

run_segment() {
    local f=$1 out
    if command -v timeout >/dev/null 2>&1; then
        out=$(printf '%s' "$input" | timeout "$SEGMENT_TIMEOUT" "$f" 2>/dev/null) || return 0
    else
        out=$(printf '%s' "$input" | "$f" 2>/dev/null) || return 0
    fi
    printf '%s' "${out%%$'\n'*}"
}

LINE=""
while IFS=$'\t' read -r name kind path; do
    frag=""
    if [ "$kind" = kit ]; then
        # NN-name.sh → seg_name（ハイフンはアンダースコアに）
        fn="${name#[0-9][0-9]-}"
        fn="seg_${fn%.sh}"
        fn="${fn//-/_}"
        # shellcheck source=/dev/null
        source "$path" 2>/dev/null
        declare -F "$fn" >/dev/null && frag=$("$fn")
    else
        frag=$(run_segment "$path")
    fi
    [ -n "$frag" ] || continue
    if [ -z "$LINE" ]; then
        LINE="$frag"
    else
        LINE="$LINE | $frag"
    fi
done < <(list_parts | sort -t$'\t' -k1,1)

printf '%s\n' "$LINE"
