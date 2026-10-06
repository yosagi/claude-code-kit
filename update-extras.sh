#!/bin/bash
# 目的: キット外のスキル群を claude-registry/dist-extras/<route>/ に配置し、stamp 更新 + install を行う
# 関連: update-registry.sh, setup_global.sh (install_extras), install-skill.sh
# 前提: ~/Notes/claude-registry/dist/ にキットが配置済みであること（setup_global.sh を呼ぶため）
#
# Usage: update-extras.sh <route-name> <source-dir>
#
#   <route-name>  配布経路の名前。配布元がわかる名前にする（例: claude-dist-skills）
#   <source-dir>  配布物を並べたディレクトリ。次の2つの形式を受け付ける:
#
#                 構造化レイアウト（直下に skills/ または installers/ がある）
#                   skills/<name>/   スキル本体
#                   installers/<f>   自分をインストールする実行ファイル
#                                    （--install / --uninstall を受け、冪等であること）
#                 従来形式（どちらも無い）
#                   直下のディレクトリをすべてスキルとして扱う
#
#                 どちらの形式でも、直下に `deprecated` ファイルがあれば
#                 廃止リストとして一緒に配信する
#
# キットは dist-extras の「規約」だけを知り、中身には関知しない。
# 実行後、他PCでは claude-code 起動時に auto-install が発火して反映される。

set -euo pipefail

REGISTRY_DIST="$HOME/Notes/claude-registry/dist"
EXTRAS_DIR="$HOME/Notes/claude-registry/dist-extras"

GREEN='\033[0;32m'
NC='\033[0m'
info() { echo -e "${GREEN}[INFO]${NC} $1"; }

ROUTE="${1:-}"
SRC="${2:-}"

if [[ -z "$ROUTE" || -z "$SRC" ]]; then
    echo "Usage: $(basename "$0") <route-name> <source-dir>" >&2
    exit 1
fi

# 経路名はディレクトリ名として使うため、区切り文字等を弾く
if [[ ! "$ROUTE" =~ ^[A-Za-z0-9._-]+$ || "$ROUTE" == .* ]]; then
    echo "error: 経路名に使えない文字が含まれています: $ROUTE" >&2
    exit 1
fi

if [[ ! -d "$SRC" ]]; then
    echo "error: ソースディレクトリが見つかりません: $SRC" >&2
    exit 1
fi

SRC_ABS="$(cd "$SRC" && pwd)"
ROUTE_DIR="$EXTRAS_DIR/$ROUTE"

# registry 内のコピーを発信元にすると自分自身を rsync することになる
if [[ "$SRC_ABS" == "$EXTRAS_DIR"* ]]; then
    echo "error: registry 内のコピーから実行されています。" >&2
    echo "更新は発信元（開発リポジトリ）側から実行してください。" >&2
    exit 1
fi

if [[ ! -x "$REGISTRY_DIST/setup_global.sh" ]]; then
    echo "error: キットが registry に配置されていません: $REGISTRY_DIST" >&2
    echo "先に update-registry.sh を実行してください。" >&2
    exit 1
fi

# 配布物を配置（deprecated は skills/ の中には送らない）
# 構造化レイアウトかどうかは、直下に skills/ か installers/ があるかで判定する
sync_subdir() {
    local sub="$1"
    if [[ -d "$SRC_ABS/$sub" ]]; then
        info "$SRC_ABS/$sub/ → $ROUTE_DIR/$sub/"
        mkdir -p "$ROUTE_DIR/$sub"
        rsync -a --delete "$SRC_ABS/$sub/" "$ROUTE_DIR/$sub/"
    else
        # 経路から取り除く（配布をやめた場合）
        rm -rf "${ROUTE_DIR:?}/$sub"
    fi
}

if [[ -d "$SRC_ABS/skills" || -d "$SRC_ABS/installers" ]]; then
    sync_subdir skills
    sync_subdir installers
else
    info "$SRC_ABS/ → $ROUTE_DIR/skills/"
    mkdir -p "$ROUTE_DIR/skills"
    rsync -a --delete --exclude='deprecated' "$SRC_ABS/" "$ROUTE_DIR/skills/"
    rm -rf "${ROUTE_DIR:?}/installers"
fi

# 廃止リストを配置（無ければ経路から取り除く）
if [[ -f "$SRC_ABS/deprecated" ]]; then
    cp "$SRC_ABS/deprecated" "$ROUTE_DIR/deprecated"
    info "deprecated: $(grep -cve '^\s*\(#.*\)\?$' "$ROUTE_DIR/deprecated" || true) 件"
else
    rm -f "$ROUTE_DIR/deprecated"
fi

# stamp 更新（rsync --delete で消えた後に書く）
date +%s > "$ROUTE_DIR/.extras-stamp"
info "stamp: $(cat "$ROUTE_DIR/.extras-stamp")"

# このPCにも反映（ローカル stamp は setup_global.sh の install_extras が更新する）
info "setup_global.sh --install"
"$REGISTRY_DIST/setup_global.sh" --install
