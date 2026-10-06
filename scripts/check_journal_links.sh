#!/bin/bash
# 目的: journals ファイル内の会話ログリンクが実在するか確認し、リンク切れを修復する
# 関連: work-logger スキル, ccexport
# 前提: ~/Notes/journals/*.org に会話ログリンクが記載されている
#
# 使い方:
#   check_journal_links.sh              # リンク切れ確認（dry-run）
#   check_journal_links.sh --fix        # セッションIDマッチでリネーム修復
#   check_journal_links.sh --fix DIR    # journals ディレクトリ指定

FIX=false
JOURNALS_DIR="$HOME/Notes/journals"

for arg in "$@"; do
    case "$arg" in
        --fix) FIX=true ;;
        *) JOURNALS_DIR="$arg" ;;
    esac
done

SESSION_DIR="$JOURNALS_DIR/claude_sessions"
TOTAL=0
BROKEN=0
FIXED=0
UNFIXABLE=0

while IFS= read -r line; do
    journal_file="${line%%:*}"
    rest="${line#*:}"

    while [[ "$rest" =~ \[\[file:(claude_sessions/[^]]+)\] ]]; do
        rel_path="${BASH_REMATCH[1]}"
        rel_path="${rel_path%%\]*}"
        abs_path="$JOURNALS_DIR/$rel_path"
        TOTAL=$((TOTAL + 1))

        if [[ ! -f "$abs_path" ]]; then
            filename="${rel_path##*/}"
            # セッションID（末尾の _XXXXXXXX.org）を抽出
            session_id="${filename%.org}"
            session_id="${session_id##*_}"

            if [[ ${#session_id} -eq 8 ]]; then
                # セッションIDで既存ファイルを検索
                candidates=("$SESSION_DIR"/*"_${session_id}.org")
                if [[ -f "${candidates[0]}" && ${#candidates[@]} -eq 1 ]]; then
                    actual="${candidates[0]##*/}"
                    if $FIX; then
                        mv "$candidates" "$abs_path"
                        echo "FIXED: $actual -> $filename"
                        FIXED=$((FIXED + 1))
                    else
                        echo "FIXABLE: $actual -> $filename"
                        FIXED=$((FIXED + 1))
                    fi
                else
                    echo "BROKEN: $journal_file -> $rel_path (no match for session $session_id)"
                    UNFIXABLE=$((UNFIXABLE + 1))
                fi
            else
                echo "BROKEN: $journal_file -> $rel_path (cannot extract session ID)"
                UNFIXABLE=$((UNFIXABLE + 1))
            fi
            BROKEN=$((BROKEN + 1))
        fi

        rest="${rest#*"${BASH_REMATCH[0]}"}"
    done
done < <(grep -n 'file:claude_sessions/' "$JOURNALS_DIR"/*.org 2>/dev/null)

echo ""
echo "Total: $TOTAL, Broken: $BROKEN, Fixable: $FIXED, Unfixable: $UNFIXABLE"

if $FIX && [[ $FIXED -gt 0 ]]; then
    echo "Renamed $FIXED file(s)."
fi

if [[ $BROKEN -eq 0 ]]; then
    echo "All links are valid."
elif [[ $UNFIXABLE -eq 0 && ! $FIX ]]; then
    echo "Run with --fix to rename and repair."
fi

[[ $UNFIXABLE -eq 0 ]] || exit 1
