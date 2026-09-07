#!/bin/bash
# 目的: このディレクトリ（dist 内容）を claude-registry に配置し、stamp 更新 + setup_global.sh --install を実行する
# 関連: setup_global.sh, bootstrap.sh, scripts/claude-code (auto-install)
# 前提: ~/Notes/claude-registry/ が存在すること（Syncthing 等で同期される想定。1台運用ならローカルディレクトリのまま）
#
# 発信側（開発リポジトリの dist/）とフォロワー（キットの clone）の両方で使う。
# フォロワーの更新手順: git pull && ./update-registry.sh
# 実行後、他PCでは claude-code 起動時に auto-install が発火して反映される。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REGISTRY_DIST="$HOME/Notes/claude-registry/dist"
STAMP_FILE="$REGISTRY_DIST/.dist-stamp"
LOCAL_STAMP="$HOME/.claude/.dist-stamp"

GREEN='\033[0;32m'
NC='\033[0m'
info() { echo -e "${GREEN}[INFO]${NC} $1"; }

if [[ "$SCRIPT_DIR" == "$(cd "$REGISTRY_DIST" 2>/dev/null && pwd)" ]]; then
    echo "error: registry 内のコピーから実行されています。" >&2
    echo "更新は clone（または開発リポジトリの dist/）側から実行してください。" >&2
    exit 1
fi

# dist 内容を registry にコピー
info "$SCRIPT_DIR/ → $REGISTRY_DIST"
mkdir -p "$REGISTRY_DIST"
rsync -a --delete "$SCRIPT_DIR/" "$REGISTRY_DIST/"

# stamp 更新（rsync --delete で消えた後に書く）
date +%s > "$STAMP_FILE"
info "stamp: $(cat "$STAMP_FILE")"

# registry のコピーから install
info "setup_global.sh --install"
"$REGISTRY_DIST/setup_global.sh" --install

# このPCは今 install したので、ローカル stamp を同期して次回起動時の
# auto-install 空回りを防ぐ（wrapper の auto-install 成功時と同じ処理）
mkdir -p "$(dirname "$LOCAL_STAMP")"
cp "$STAMP_FILE" "$LOCAL_STAMP"
