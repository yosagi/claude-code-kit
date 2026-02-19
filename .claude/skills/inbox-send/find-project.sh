#!/bin/bash
# 目的: 全プロジェクトの project_title.txt を収集して一覧表示・検索
# 関連: inbox-send スキル（送信先の探索）
# 前提: ccexport がインストールされていること
#
# 使い方:
#   find-project.sh          全プロジェクト一覧
#   find-project.sh キーワード  パス・プロジェクト名・人格名・概要で絞り込み
#
# 出力形式（タブ区切り）:
#   /path/to/project\tプロジェクト名 / 人格名 : 概要

if ! command -v ccexport >/dev/null 2>&1; then
    echo "Error: ccexport is required" >&2
    exit 1
fi

KEYWORD="$1"

ccexport projects 2>/dev/null | while read -r project_path; do
    title_file="$project_path/reports/project_title.txt"
    if [[ -f "$title_file" ]]; then
        line=$(printf '%s\t%s' "$project_path" "$(head -1 "$title_file")")
    else
        line="$project_path"
    fi
    if [[ -z "$KEYWORD" ]] || echo "$line" | grep -qi "$KEYWORD"; then
        echo "$line"
    fi
done
