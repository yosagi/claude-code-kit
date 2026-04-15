#!/bin/bash
# 目的: work-logger 用のセッション情報取得
# 用途:
#   get_session_info.sh --project <session_id>  → プロジェクト名を出力
#   get_session_info.sh --opt-in <session_id>   → "有効" または "無効" を出力

set -e

case "$1" in
    --project)
        if [ -z "$2" ]; then
            echo "unknown"
            exit 0
        fi
        # セッションIDからプロジェクト名を取得
        PROJECT=$(ccexport session-info -s "$2" --json 2>/dev/null | jq -r '.project // empty' | xargs -r basename)
        if [ -z "$PROJECT" ]; then
            echo "unknown"
        else
            echo "$PROJECT"
        fi
        ;;
    --opt-in)
        if [ -z "$2" ]; then
            echo "無効"
            exit 0
        fi
        # セッションIDからプロジェクトパスを取得
        PROJECT_ROOT=$(ccexport session-info -s "$2" --json 2>/dev/null | jq -r '.project // empty')
        if [ -z "$PROJECT_ROOT" ]; then
            echo "無効"
            exit 0
        fi
        # .claude/export_session の存在確認
        if [ -f "$PROJECT_ROOT/.claude/export_session" ]; then
            echo "有効"
        else
            echo "無効"
        fi
        ;;
    *)
        echo "Usage: $0 --project <session_id> | --opt-in <session_id>" >&2
        exit 1
        ;;
esac
