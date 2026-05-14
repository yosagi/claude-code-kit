#!/usr/bin/env bash
# ~/Notes/claude-registry/drafts/ のドラフトファイルを journals に追記する
# session_end.sh から呼ばれる。将来は定期タスクからも呼べる独立スクリプト。
#
# 追記許可ホスト（append_host.txt に記載）でのみ実行される。
#
# 新形式ファイル名: YYYY-MM-DD_HHMMSS_<skill>_<skill-specific>.org
#   → ~/.claude/skills/<skill>/append_journal.py <draft_path> を kick
#   → 各 skill の append_journal.py がファイル内容とファイル名から必要な情報を取り出す
#
# 後方互換（legacy）形式: YYYY-MM-DD_HHMMSS_<project@host>.org (3 フィールド)
#   → 3番目のフィールドを section_name として work-logger/append_journal.py を legacy 引数で呼ぶ
#
# append_journal.py が追記後にドラフトファイルを削除する

set -uo pipefail

REGISTRY_BASE="$HOME/Notes/claude-registry"
DRAFTS_DIR="$REGISTRY_BASE/drafts"
APPEND_HOST_FILE="$REGISTRY_BASE/append_host.txt"
SKILLS_DIR="$HOME/.claude/skills"

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

    # ファイル名を _ で 4 フィールドに分解
    # 新形式: [date] [time] [skill] [skill-specific]
    # legacy: [date] [time] [project@host] (rest は空)
    IFS='_' read -r date time_str third rest <<< "$basename"

    if [[ -z "$date" || -z "$time_str" || -z "$third" ]]; then
        echo "Warning: Cannot parse draft filename: $draft" >&2
        ((failed++)) || true
        continue
    fi

    if [[ -z "$rest" ]]; then
        # Legacy 形式: 3rd フィールドが section_name (project@host)
        # work-logger の旧インタフェースで呼ぶ
        APPEND_SCRIPT="$SKILLS_DIR/work-logger/append_journal.py"
        if [[ ! -x "$APPEND_SCRIPT" ]]; then
            echo "Warning: Legacy fallback script not found: $APPEND_SCRIPT" >&2
            ((failed++)) || true
            continue
        fi
        if python3 "$APPEND_SCRIPT" "$date" "$third" "$draft"; then
            ((processed++)) || true
        else
            echo "Warning: Failed to process legacy draft: $draft" >&2
            ((failed++)) || true
        fi
    else
        # 新形式: 3rd フィールドが skill 名
        skill="$third"
        APPEND_SCRIPT="$SKILLS_DIR/$skill/append_journal.py"
        if [[ ! -x "$APPEND_SCRIPT" ]]; then
            echo "Warning: Skill append script not found: $APPEND_SCRIPT (draft: $draft)" >&2
            ((failed++)) || true
            continue
        fi
        if python3 "$APPEND_SCRIPT" "$draft"; then
            ((processed++)) || true
        else
            echo "Warning: Failed to process draft: $draft" >&2
            ((failed++)) || true
        fi
    fi
done

if [[ $processed -gt 0 || $failed -gt 0 ]]; then
    echo "Journal drafts: ${processed} processed, ${failed} failed"
fi
