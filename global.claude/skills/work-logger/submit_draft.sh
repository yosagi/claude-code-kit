#!/usr/bin/env bash
# ドラフトファイルを ~/Notes/claude-registry/drafts/ に提出する
# work-logger SKILL.md の Step 4 から呼ばれる
#
# Usage: submit_draft.sh <日付> <プロジェクト名> <ドラフトファイルパス>
# Example: submit_draft.sh 2026-04-13 claude /path/to/draft.org
#
# 出力ファイル名: YYYY-MM-DD_HHMMSS_work-logger_project@hostname.org
# 3番目のフィールド (work-logger) で dispatcher がこの skill の append_journal.py に振る。
#
# 出力: 提出先のファイルパスを stdout に出力

set -euo pipefail

if [[ $# -ne 3 ]]; then
    echo "Usage: submit_draft.sh <date> <project> <draft_file>" >&2
    exit 1
fi

date="$1"
project="$2"
draft_file="$3"

if [[ ! -f "$draft_file" ]]; then
    echo "Error: Draft file not found: $draft_file" >&2
    exit 1
fi

if [[ ! -s "$draft_file" ]]; then
    echo "Error: Draft file is empty: $draft_file" >&2
    exit 1
fi

DRAFTS_DIR="$HOME/Notes/claude-registry/drafts"
mkdir -p "$DRAFTS_DIR"

hostname="$(hostname)"
time_str="$(date +%H%M%S)"
dest="${DRAFTS_DIR}/${date}_${time_str}_work-logger_${project}@${hostname}.org"

cp "$draft_file" "$dest"
rm "$draft_file"

echo "$dest"
