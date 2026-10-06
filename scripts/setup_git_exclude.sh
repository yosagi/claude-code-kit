#!/bin/bash
# 目的: claude-code-kit が使うファイル群を .git/info/exclude に登録し、
#       既に index に入ってしまっているものを追跡から外す（git rm --cached）。
#       既存プロジェクトへの適用と、init-project.sh からの呼び出し（登録のみ）の両方に使う
# 関連: persona-setup スキルの init-project.sh（新規セットアップ時にこのスクリプトを --no-untrack で呼ぶ）、
#       setup_global.sh（~/.claude/scripts/ に配置する）
# 前提: 対象が git リポジトリであること。.gitignore には一切触らない
#
# 使い方:
#   ~/.claude/scripts/setup_git_exclude.sh [PROJECT_ROOT] [--dry-run] [--no-untrack]
#
#   PROJECT_ROOT  対象プロジェクト（省略時はカレントディレクトリ）
#   --dry-run     exclude への追記も index からの除外も行わず、何が起きるかだけ表示する
#   --no-untrack  exclude への追記だけ行い、追跡済みファイルは一覧を表示するにとどめる
#
# 書き込み先は共有物の .gitignore ではなく、このクローンにだけ効く .git/info/exclude。
# キットの利用は個人の作業環境の話であり、プロジェクトの共有ファイルに痕跡を残さない。
# worktree では `git rev-parse --git-path` が共通ディレクトリ側の exclude を返すので、
# 本体と worktree で同じファイルに書かれる。
#
# index からの除外は作業ツリーのファイルを消さない（--cached）。ただし次の commit で
# リポジトリからは消えるので、実行後は差分を確認して commit すること。
# 共有している CLAUDE.md を意図的に追跡している場合は --no-untrack で登録だけ行う。

set -euo pipefail

PROJECT_ROOT="."
DRY_RUN=0
UNTRACK=1
for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=1 ;;
        --no-untrack) UNTRACK=0 ;;
        -h|--help) sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        -*) echo "不明なオプション: $arg" >&2; exit 2 ;;
        *) PROJECT_ROOT="$arg" ;;
    esac
done

# --- 登録するエントリ ---
#
# claude-code-kit が使うファイル群は registry にバックアップされるため git 管理しない。
# あわせて sandbox 実行時にプロジェクトルートへ生える一時 dotfile も無視し、
# git status を「本当にコミットすべき差分」だけが並ぶ状態に保つ。
#
# コメント行と空行はセクション見出しとして扱い、
# 同じセクションに追記すべきエントリが1つもなければ出力しない。
# 既存エントリの判定は exclude と .gitignore の両方に対して行う
# （プロジェクトの .gitignore が既に無視しているものを exclude に重ねない）。
exclude_entries=(
    "# claude-code-kit（registry にバックアップされるため git 管理しない）"
    "/reports/"
    "/scratch/"
    "/tmp/"
    "/.claude/"
    "/work_in_progress.md"
    "/CLAUDE.md"
    "/CLAUDE.local.md"
    "/.no-claude-md-sync"
    ""
    "# sandbox 実行時にプロジェクトルートへ生える一時 dotfile"
    "/.bashrc"
    "/.bash_profile"
    "/.profile"
    "/.zshrc"
    "/.zprofile"
    "/.gitconfig"
    "/.ripgreprc"
    ""
    "# 仮想環境・IDE のユーザー固有ファイル"
    ".venv/"
    ".idea/**/workspace.xml"
    ".idea/**/tasks.xml"
    ".idea/**/usage.statistics.xml"
    ".idea/**/dictionaries"
    ".idea/**/shelf"
)

# パターン行だけ（見出し・空行を除く）
patterns=()
for line in "${exclude_entries[@]}"; do
    [[ -z "$line" || "$line" == \#* ]] && continue
    patterns+=("$line")
done

# --- exclude への登録 ---
setup_git_exclude() {
    local root="$1"
    local gitignore="$root/.gitignore"

    # exclude の実パス（worktree では共通ディレクトリ側）。相対で返る場合は root 基準
    local exclude
    exclude=$(git -C "$root" rev-parse --git-path info/exclude)
    [[ "$exclude" == /* ]] || exclude="$root/$exclude"

    # 既存エントリ（行末空白と先頭の / を落として比較する。
    # README の旧案内に従った "reports/" 形式も既存とみなすため）。
    # exclude と .gitignore の両方を見る
    local existing_norm=""
    local f
    for f in "$exclude" "$gitignore"; do
        if [[ -f "$f" ]]; then
            existing_norm+=$(sed 's/[[:space:]]*$//; s|^/||' "$f")$'\n'
        fi
    done

    local out="" added=() line header="" body=()

    # 1セクション分を出力に足す（追記すべきエントリが無ければ見出しごと捨てる）
    flush_section() {
        local l
        if ((${#body[@]} == 0)); then
            header=""
            return 0
        fi
        if [[ -n "$out" ]]; then
            out+=$'\n'
        fi
        if [[ -n "$header" ]] && ! grep -Fxq -- "$header" <<<"$existing_norm"; then
            out+="$header"$'\n'
        fi
        for l in "${body[@]}"; do
            out+="$l"$'\n'
        done
        added+=("${body[@]}")
        header=""
        body=()
    }

    for line in "${exclude_entries[@]}"; do
        if [[ -z "$line" ]]; then
            flush_section
        elif [[ "$line" == \#* ]]; then
            header="$line"
        elif ! grep -Fxq -- "${line#/}" <<<"$existing_norm"; then
            body+=("$line")
        fi
    done
    flush_section

    if ((${#added[@]} == 0)); then
        echo "  .git/info/exclude: 追記なし（すべて設定済み）"
        return 0
    fi

    if ((DRY_RUN)); then
        echo "  .git/info/exclude: ${#added[@]} 件のエントリを追記します（dry-run、$exclude）"
        printf '    %s\n' "${added[@]}"
        return 0
    fi

    # 既存ファイルが改行で終わっていなければ補い、区切りの空行を入れる
    mkdir -p "$(dirname "$exclude")"
    if [[ -s "$exclude" ]]; then
        if [[ -n "$(tail -c 1 "$exclude")" ]]; then
            printf '\n' >> "$exclude"
        fi
        printf '\n' >> "$exclude"
    fi
    printf '%s' "$out" >> "$exclude"

    echo "  .git/info/exclude: ${#added[@]} 件のエントリを追記しました（$exclude）"
    printf '    %s\n' "${added[@]}"
}

# --- index からの除外 ---
#
# 「追跡済み、かつ登録パターンに当たるもの」を git 自身に判定させる。
# exclude や .gitignore の中身ではなく登録パターンだけを --exclude-from で渡すので、
# プロジェクト側が意図的に force-add した別のファイルを巻き込まない。
untrack_kit_files() {
    local root="$1"
    local patfile
    patfile=$(mktemp "${TMPDIR:-/tmp}/kit-exclude.XXXXXX")
    printf '%s\n' "${patterns[@]}" > "$patfile"

    local tracked=()
    while IFS= read -r -d '' f; do
        tracked+=("$f")
    done < <(git -C "$root" ls-files -z --cached -i --exclude-from="$patfile")
    rm -f "$patfile"

    if ((${#tracked[@]} == 0)); then
        echo "  index: 追跡済みのキット関連ファイルはありません"
        return 0
    fi

    if ((!UNTRACK)); then
        echo "  index: 以下 ${#tracked[@]} 件は追跡済みです（--no-untrack のため外していません）"
        printf '    %s\n' "${tracked[@]}"
        echo "  追跡から外すには: $(basename "$0") $root"
        return 0
    fi

    if ((DRY_RUN)); then
        echo "  index: 以下 ${#tracked[@]} 件を追跡から外します（dry-run、ファイルは残ります）"
        printf '    %s\n' "${tracked[@]}"
        return 0
    fi

    printf '%s\0' "${tracked[@]}" | git -C "$root" rm --cached -q --pathspec-from-file=- --pathspec-file-nul
    echo "  index: ${#tracked[@]} 件を追跡から外しました（ファイルは残っています。次の commit でリポジトリから消えます）"
    printf '    %s\n' "${tracked[@]}"
}

# --- main ---
if [[ ! -e "$PROJECT_ROOT/.git" ]]; then
    echo "  .git/info/exclude: git リポジトリではないためスキップ"
    exit 0
fi
if ! git -C "$PROJECT_ROOT" rev-parse --git-dir >/dev/null 2>&1; then
    echo "  .git/info/exclude: git リポジトリとして解決できないためスキップ"
    exit 0
fi

setup_git_exclude "$PROJECT_ROOT"
untrack_kit_files "$PROJECT_ROOT"
