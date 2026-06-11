#!/bin/bash
# 目的: プロジェクトの状態（reports/ 等）を registry にバックアップする
# 関連: session_end.sh から nohup+disown で起動される
# 前提: ~/Notes/claude-registry/ が存在すること

set -euo pipefail

REGISTRY_BASE="$HOME/Notes/claude-registry"

# プロジェクトパスから registry のディレクトリ名を生成
# $HOME を省略し、/ → -, . → - で変換（session_start.sh と同じロジック）
path_to_dirname() {
    local path="$1"
    echo "${path#$HOME/}" | sed 's|/|-|g; s|\.|-|g'
}

backup_project_state() {
    local project_dir="$1"
    local session_id="${2:-}"

    # reports/ が symlink なら実体は別プロジェクトにあるのでスキップ
    if [[ -L "$project_dir/reports" ]]; then
        return 0
    fi

    # reports/ がなければ何もしない
    if [[ ! -d "$project_dir/reports" ]]; then
        return 0
    fi

    local hostname
    hostname=$(hostname)
    local dir_name
    dir_name=$(path_to_dirname "$project_dir")
    local states_dir="$REGISTRY_BASE/$hostname/$dir_name/states"

    mkdir -p "$states_dir"

    # reports/ をまるごと同期
    rsync -a --delete "$project_dir/reports/" "$states_dir/reports/"

    # プロジェクトルート直下の重要ファイルをコピー
    for f in CLAUDE.md CLAUDE.local.md work_in_progress.md; do
        if [[ -f "$project_dir/$f" ]]; then
            rsync -a "$project_dir/$f" "$states_dir/$f"
        else
            # プロジェクト側で消えていたら states 側も消す
            rm -f "$states_dir/$f"
        fi
    done

    # マニフェストを生成
    local manifest="$states_dir/.backup_manifest"
    local timestamp
    timestamp=$(date '+%Y-%m-%dT%H:%M:%S')

    {
        echo "# backup: $timestamp session:${session_id:0:8}"
        # reports/ 以下のファイル一覧（サイズ パス）
        (cd "$project_dir" && find reports/ -type f -printf '%s %p\n' | sort -k2)
        # ルート直下ファイル
        for f in CLAUDE.md CLAUDE.local.md work_in_progress.md; do
            if [[ -f "$project_dir/$f" ]]; then
                (cd "$project_dir" && find "$f" -maxdepth 0 -type f -printf '%s %p\n')
            fi
        done
    } > "$manifest"
}

# メイン: 引数でプロジェクトディレクトリとセッションIDを受け取る
project_dir="${1:-}"
session_id="${2:-}"

if [[ -z "$project_dir" ]]; then
    echo "Usage: $0 <project_dir> [session_id]" >&2
    exit 1
fi

backup_project_state "$project_dir" "$session_id"
