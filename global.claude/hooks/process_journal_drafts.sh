#!/usr/bin/env bash
# ~/Notes/claude-registry/drafts/ のドラフトファイルを journals に追記する
# session_end.sh から呼ばれる。将来は定期タスクからも呼べる独立スクリプト。
#
# 追記許可ホスト（append_host.txt に記載）でのみ実行される。
# 各ドラフトのファイル名: YYYY-MM-DD_HHMMSS_sectionname.org
#   → append_journal.py に (日付, セクション名, ファイルパス) を渡す
#   → append_journal.py が追記後にドラフトファイルを削除する

set -uo pipefail

REGISTRY_BASE="$HOME/Notes/claude-registry"
DRAFTS_DIR="$REGISTRY_BASE/drafts"
APPEND_HOST_FILE="$REGISTRY_BASE/append_host.txt"

# append_journal.py のパス（グローバルインストール先）
APPEND_JOURNAL="$HOME/.claude/skills/work-logger/append_journal.py"

# 追記許可ホストチェック
if [[ ! -f "$APPEND_HOST_FILE" ]]; then
    exit 0
fi

append_host="$(cat "$APPEND_HOST_FILE" | tr -d '[:space:]')"
current_host="$(hostname)"

if [[ "$current_host" != "$append_host" ]]; then
    exit 0
fi

# ドラフトディレクトリがなければ何もしない
if [[ ! -d "$DRAFTS_DIR" ]]; then
    exit 0
fi

# ドラフトファイルをソート順（時系列）で処理
processed=0
failed=0

for draft in $(ls "$DRAFTS_DIR"/*.org 2>/dev/null | sort); do
    basename="$(basename "$draft" .org)"

    # ファイル名パース: YYYY-MM-DD_HHMMSS_sectionname
    # _ で分割: [YYYY-MM-DD] [HHMMSS] [section@host]
    IFS='_' read -r date time_str section_name <<< "$basename"

    if [[ -z "$date" || -z "$section_name" ]]; then
        echo "Warning: Cannot parse draft filename: $draft" >&2
        ((failed++)) || true
        continue
    fi

    if python3 "$APPEND_JOURNAL" "$date" "$section_name" "$draft"; then
        ((processed++)) || true
    else
        echo "Warning: Failed to process draft: $draft" >&2
        ((failed++)) || true
    fi
done

if [[ $processed -gt 0 || $failed -gt 0 ]]; then
    echo "Journal drafts: ${processed} processed, ${failed} failed"
fi
