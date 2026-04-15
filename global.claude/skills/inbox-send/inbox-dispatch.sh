#!/bin/bash
# 目的: 受信側プロジェクトで claude -p を起動して inbox 依頼を自動処理
# 関連: inbox-send SKILL.md, inbox-process SKILL.md
# 前提: 依頼ファイルが既に送信済みであること

set -e

usage() {
    cat << 'EOF'
Usage:
  inbox-dispatch.sh <dest_project_path> <request_filename> [--ephemeral]

Arguments:
  dest_project_path  - 受信側プロジェクトのパス（例: ~/work/myproject）
                       リモートの場合: remote:hostname:/path/to/project
  request_filename   - 送信した依頼ファイル名（例: 2026-02-05_from_claude_topic.md）

Options:
  --ephemeral        - 軽量版で処理（実装ログ・work_history 更新なし）

Example:
  inbox-dispatch.sh ~/work/myproject 2026-02-05_from_claude_request.md
  inbox-dispatch.sh remote:pc-b:~/work/wip 2026-02-05_from_claude_request.md --ephemeral

This script:
  1. Creates inbox-logs directory if needed
  2. Runs claude -p "/inbox-process <filename>" in the destination project
  3. Outputs to a log file in reports/inbox-logs/
  4. Runs in background (returns immediately)
  5. For remote destinations, uses ssh + tmux for resilience
EOF
    exit 1
}

if [ $# -lt 2 ]; then
    usage
fi

DEST_PROJECT="$1"
REQUEST_FILENAME="$2"
SKILL="inbox-process"

if [ "${3:-}" = "--ephemeral" ]; then
    SKILL="inbox-process-ephemeral"
fi

# ログファイル名用のタイムスタンプとトピック
TIMESTAMP=$(date +%Y-%m-%d_%H%M%S)
TOPIC=$(echo "$REQUEST_FILENAME" | sed 's/^[0-9-]*_from_[^_]*_//' | sed 's/\.md$//')

CLAUDE_CMD="unset CLAUDECODE && claude -p \"/${SKILL} ${REQUEST_FILENAME} を処理して\" --permission-mode acceptEdits --allowedTools \"Bash Edit Read Write Grep Glob\" --settings '{\"sandbox\":{\"allowUnsandboxedCommands\": false}}'"

if [[ "$DEST_PROJECT" == remote:* ]]; then
    # --- リモート実行 ---
    HOST=$(echo "$DEST_PROJECT" | cut -d: -f2)
    REMOTE_PATH=$(echo "$DEST_PROJECT" | cut -d: -f3-)

    # tmux セッション名（衝突しないようにタイムスタンプ付き）
    TMUX_SESSION="inbox-${TOPIC}-${TIMESTAMP}"

    echo "Starting inbox-process on remote host..."
    echo "  Host: $HOST"
    echo "  Project: $REMOTE_PATH"
    echo "  Request: $REQUEST_FILENAME"
    echo "  tmux session: $TMUX_SESSION"

    # リモート側のスクリプトで tmux セッションを作成して claude -p を実行
    REMOTE_SCRIPT="~/.claude/skills/inbox-send/inbox-remote-dispatch.sh"
    ssh "$HOST" "$REMOTE_SCRIPT" "$REMOTE_PATH" "$REQUEST_FILENAME" "$SKILL" "$TMUX_SESSION"

    echo ""
    echo "=== Dispatch Complete (Remote) ==="
    echo "Process running in tmux on $HOST. Check with: ssh $HOST tmux attach -t $TMUX_SESSION"
else
    # --- ローカル実行（既存の動作） ---
    # パスを展開（~ を解決）
    DEST_PROJECT=$(eval echo "$DEST_PROJECT")

    # プロジェクトの存在確認
    if [ ! -d "$DEST_PROJECT" ]; then
        echo "Error: Destination project not found: $DEST_PROJECT"
        exit 1
    fi

    # ログディレクトリを作成
    LOG_DIR="${DEST_PROJECT}/reports/inbox-logs"
    mkdir -p "$LOG_DIR"
    LOG_FILE="${LOG_DIR}/${TIMESTAMP}_${TOPIC}.log"

    echo "Starting inbox-process in background..."
    echo "  Project: $DEST_PROJECT"
    echo "  Request: $REQUEST_FILENAME"
    echo "  Log: $LOG_FILE"

    (
        cd "$DEST_PROJECT" && \
        eval "$CLAUDE_CMD" > "$LOG_FILE" 2>&1
    ) &

    DISPATCH_PID=$!
    echo "  PID: $DISPATCH_PID"
    echo ""
    echo "=== Dispatch Complete ==="
    echo "Process running in background. Check log file for progress."
fi
