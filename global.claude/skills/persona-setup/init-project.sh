#!/bin/bash
# 目的: reports/ 基本構造の作成と .git/info/exclude の調整（既存ファイルを壊さない、べき等）
# 関連: persona-setup スキル、bootstrap.sh、backup_project_state.sh
# 前提: なし（exclude の調整は git リポジトリのときのみ行う。.gitignore には触らない）

set -euo pipefail

PROJECT_ROOT="${1:-.}"

# ディレクトリ作成（mkdir -p でべき等）
dirs=(
    reports/ideas/done reports/ideas/rejected
    reports/todos/done reports/todos/rejected
    reports/inbox/done
    reports/draft
    reports/kb
    reports/tasks
    reports/misc
    reports/memory
    reports/personas
    reports/insight
    reports/status
    reports/jobs/done
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

# --- .git/info/exclude の調整 ---
#
# エントリの登録は保守用ツール ~/.claude/scripts/setup_git_exclude.sh に一本化している
# （setup_global.sh --install で配置される）。
# 新規セットアップでは登録のみ行い、追跡済みファイルがあっても外さない（--no-untrack）。
# 既に追跡されている CLAUDE.md をチームで共有している可能性があるため、
# index から外すのは利用者の判断で setup_git_exclude.sh を直接実行して行う。
EXCLUDE_TOOL="${SETUP_GIT_EXCLUDE:-$HOME/.claude/scripts/setup_git_exclude.sh}"   # 環境変数はテスト用の差し替え口
if [[ ! -e "$PROJECT_ROOT/.git" ]]; then
    echo "  .git/info/exclude: git リポジトリではないためスキップ"
elif [[ ! -x "$EXCLUDE_TOOL" ]]; then
    echo "  .git/info/exclude: $EXCLUDE_TOOL が無いためスキップ（setup_global.sh --install で配置される）"
else
    "$EXCLUDE_TOOL" "$PROJECT_ROOT" --no-untrack
fi
