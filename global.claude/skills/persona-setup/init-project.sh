#!/bin/bash
# 目的: reports/ 基本構造を作成する（既存ファイルを壊さない、べき等）
# 関連: persona-setup スキル、bootstrap.sh
# 前提: なし

set -euo pipefail

PROJECT_ROOT="${1:-.}"

# ディレクトリ作成（mkdir -p でべき等）
dirs=(
    reports/ideas/done reports/ideas/rejected
    reports/todos/done reports/todos/rejected
    reports/inbox/done reports/inbox/draft
    reports/kb
    reports/tasks
    reports/misc
    reports/memory
    reports/personas
    reports/insight
    reports/pub
)
for d in "${dirs[@]}"; do
    mkdir -p "$PROJECT_ROOT/$d"
done

# INDEX.md の作成（存在しなければのみ）
create_if_missing() {
    local file="$1" content="$2"
    if [[ ! -f "$PROJECT_ROOT/$file" ]]; then
        printf '%s\n' "$content" > "$PROJECT_ROOT/$file"
        echo "  作成: $file"
    fi
}

create_if_missing "reports/ideas/INDEX.md" "# IDEAS インデックス

アイデア段階の項目一覧。詳細は各ファイルを参照。"

create_if_missing "reports/todos/INDEX.md" "# TODO インデックス

タスク一覧。詳細は各ファイルを参照。"

create_if_missing "reports/inbox/INDEX.md" "# INBOX インデックス

外部プロジェクトからの依頼一覧。詳細は \`/inbox read [ファイル名]\` で確認する（既読化のため直接読まない）。"

create_if_missing "reports/kb/INDEX.md" "# KB インデックス

調査結果のナレッジベース。詳細は各ファイルを参照。"

create_if_missing "work_in_progress.md" "# Work in Progress

（進行中の作業なし）"

echo "reports/ 構造の確認・作成が完了しました。"
