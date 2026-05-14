#!/usr/bin/env bash
# note-logger のドラフトを ~/Notes/claude-registry/drafts/ に提出する
# note-logger SKILL.md の submit ステップから呼ばれる
#
# Usage: submit_draft.sh <project> <title> <draft_body_file>
# Example: submit_draft.sh claude "sandbox regression 調査" /path/to/body.org
#
# 本文ファイルは本文のみを含む（org ヘッダ/見出し無し）。
# このスクリプトが "** HH:MM [project@host] title" の header を付与し、
# 完成形ドラフトを DRAFTS_DIR に配置する。
# ファイル名: YYYY-MM-DD_HHMMSS_note-logger_<project>@<hostname>.org
# 日付は journal 日付（午前3時までは前日扱い）。
#
# 提出後、本文ファイルは削除する。
# 続けて dispatcher (process_journal_drafts.sh) を inline kick する。
# dispatcher 自身が append_host.txt を見て書き込み権限のある PC でのみ実処理を行うため、
# append host なら即時反映、それ以外では no-op で害なし。
# （session_end hook 経由での sweep にも引き続き乗る。）
# 出力: 提出先のファイルパスを stdout に出力

set -euo pipefail

if [[ $# -ne 3 ]]; then
    echo "Usage: submit_draft.sh <project> <title> <draft_body_file>" >&2
    exit 1
fi

project="$1"
title="$2"
body_file="$3"

if [[ ! -f "$body_file" ]]; then
    echo "Error: Body file not found: $body_file" >&2
    exit 1
fi

if [[ ! -s "$body_file" ]]; then
    echo "Error: Body file is empty: $body_file" >&2
    exit 1
fi

# journal 日付（午前3時までは前日）
hour=$(date +%H)
if [[ "$hour" -lt 3 ]]; then
    date_str=$(date -d "yesterday" +%Y-%m-%d)
else
    date_str=$(date +%Y-%m-%d)
fi

time_str=$(date +%H%M%S)
hhmm=$(date +%H:%M)
hostname="$(hostname)"

DRAFTS_DIR="$HOME/Notes/claude-registry/drafts"
mkdir -p "$DRAFTS_DIR"

dest="${DRAFTS_DIR}/${date_str}_${time_str}_note-logger_${project}@${hostname}.org"

# 完成形（** header + body）を書き出す
{
    echo "** ${hhmm} [${project}@${hostname}] ${title}"
    cat "$body_file"
} > "$dest"

rm "$body_file"

# dispatcher を inline kick。append host では即時反映、それ以外では早期 return で no-op
DISPATCHER="$HOME/.claude/hooks/process_journal_drafts.sh"
if [[ -x "$DISPATCHER" ]]; then
    "$DISPATCHER" >&2 || true
fi

echo "$dest"
