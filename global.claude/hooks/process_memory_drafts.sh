#!/usr/bin/env bash
# SessionEnd hook: tmp/ の記憶ドラフトを main + archive に追記
#
# ドラフトファイル:
#   tmp/work_history_draft.md  → reports/memory/work_history.md + work_history_archive.md
#   tmp/diary_draft.md         → reports/personas/diary.md + diary_archive.md
#
# CLAUDE_PROJECT_DIR 環境変数でプロジェクトルートを特定する。
# session_end.sh とは別の SessionEnd hook エントリとして登録。

set -uo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-}"
if [[ -z "$PROJECT_DIR" ]]; then
    exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TMP_DIR="$PROJECT_DIR/tmp"

processed=0
failed=0

for target in work_history diary; do
    draft="$TMP_DIR/${target}_draft.md"
    [[ -f "$draft" ]] || continue

    if python3 "$SCRIPT_DIR/append_memory_entry.py" "$draft" "$target" "$PROJECT_DIR"; then
        ((processed++)) || true
    else
        echo "Warning: Failed to process memory draft: $draft" >&2
        ((failed++)) || true
    fi
done

if [[ $processed -gt 0 || $failed -gt 0 ]]; then
    echo "Memory drafts: ${processed} processed, ${failed} failed"
fi
