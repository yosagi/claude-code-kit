#!/bin/bash
# 目的: 全プロジェクトの project_title.txt を収集して一覧表示・検索
# 関連: inbox-send スキル（送信先の探索）
# 前提: ccexport がインストールされていること（ローカル検索用）
#
# 使い方:
#   find-project.sh          全プロジェクト一覧
#   find-project.sh キーワード  パス・プロジェクト名・人格名・概要で絞り込み
#
# 出力形式（タブ区切り）:
#   ローカル:  /path/to/project\tプロジェクト名 / 人格名 : 概要
#   リモート:  remote:hostname:/path/to/project\tプロジェクト名 / 人格名 : 概要

KEYWORD="$1"
REGISTRY_BASE="$HOME/Notes/claude-registry"
MY_HOSTNAME=$(hostname)

# --- ローカルプロジェクト（既存の動作） ---
if command -v ccexport >/dev/null 2>&1; then
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
fi

# --- リモートプロジェクト（registry から検索） ---
if [[ -d "$REGISTRY_BASE" ]]; then
    for host_dir in "$REGISTRY_BASE"/*/; do
        [[ -d "$host_dir" ]] || continue
        local_hostname=$(basename "$host_dir")

        # 自PCはスキップ（ローカル検索で既にカバー済み）
        [[ "$local_hostname" = "$MY_HOSTNAME" ]] && continue

        for proj_dir in "$host_dir"/*/; do
            [[ -d "$proj_dir" ]] || continue
            title_file="$proj_dir/project_title.txt"
            [[ -f "$title_file" ]] || continue

            # 1行目: タイトル, 2行目: 実パス
            title=$(head -1 "$title_file")
            remote_path=$(sed -n '2p' "$title_file")
            [[ -z "$remote_path" ]] && continue

            line=$(printf 'remote:%s:%s\t%s' "$local_hostname" "$remote_path" "$title")
            if [[ -z "$KEYWORD" ]] || echo "$line" | grep -qi "$KEYWORD"; then
                echo "$line"
            fi
        done
    done
fi
