#!/bin/bash
# 目的: リモートから呼ばれて tmux 内で claude -p による inbox 自動処理を起動する
# 関連: inbox-dispatch.sh（SSH 経由でこのスクリプトを呼ぶ）
# 前提: tmux, claude がインストールされていること
#
# 使い方（SSH 経由で呼ばれる想定）:
#   ssh host ~/.claude/skills/inbox-send/inbox-remote-dispatch.sh <project_path> <request_filename> <skill> <tmux_session>

set -euo pipefail

if [[ $# -lt 4 ]]; then
    echo "Usage: inbox-remote-dispatch.sh <project_path> <request_filename> <skill> <tmux_session>" >&2
    exit 1
fi

PROJECT_PATH="$1"
REQUEST_FILENAME="$2"
SKILL="$3"
TMUX_SESSION="$4"

if [[ ! -d "$PROJECT_PATH" ]]; then
    echo "Error: project not found: $PROJECT_PATH" >&2
    exit 1
fi

LOG_DIR="${PROJECT_PATH}/reports/inbox-logs"
mkdir -p "$LOG_DIR"

TIMESTAMP=$(date +%Y-%m-%d_%H%M%S)
TOPIC=$(echo "$REQUEST_FILENAME" | sed 's/^[0-9-]*_from_[^_]*_//' | sed 's/\.md$//')
LOG_FILE="${LOG_DIR}/${TIMESTAMP}_${TOPIC}.log"

tmux new-session -d -s "$TMUX_SESSION" \
    "cd '$PROJECT_PATH' && unset CLAUDECODE && claude -p '/${SKILL} ${REQUEST_FILENAME} を処理して' --permission-mode acceptEdits --allowedTools 'Bash Edit Read Write Grep Glob' --settings '{\"sandbox\":{\"allowUnsandboxedCommands\": false}}' > '$LOG_FILE' 2>&1"

echo "tmux session: $TMUX_SESSION"
echo "log: $LOG_FILE"
