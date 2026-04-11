#!/bin/bash
# 目的: リモートPCの初期セットアップ（依存ツール導入 + グローバル設定インストール）
# 関連: setup_global.sh, README.md
# 前提: git, curl が使えること。このリポジトリが clone 済みであること。sudo が使えること（jq 導入時）。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# 色付き出力
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }

# OS 判定
detect_os() {
    if [[ "$(uname)" == "Darwin" ]]; then
        echo "macos"
    elif [[ -f /etc/debian_version ]]; then
        echo "debian"
    elif [[ -f /etc/redhat-release ]]; then
        echo "redhat"
    else
        echo "unknown"
    fi
}

OS=$(detect_os)

# --- Step 1: 依存ツールのインストール ---

install_jq() {
    if command -v jq >/dev/null 2>&1; then
        info "jq: $(jq --version) (インストール済み)"
        return 0
    fi

    info "jq をインストール中..."
    case "$OS" in
        macos)  brew install jq ;;
        debian) sudo apt-get install -y jq ;;
        redhat) sudo dnf install -y jq ;;
        *)
            error "jq の自動インストールに対応していない OS です。手動でインストールしてください。"
            return 1
            ;;
    esac
    info "jq: $(jq --version) をインストールしました"
}

ensure_uv() {
    if command -v uv >/dev/null 2>&1; then
        return 0
    fi

    info "uv をインストール中..."
    curl -LsSf https://astral.sh/uv/install.sh | sh
    export PATH="$HOME/.local/bin:$PATH"
    info "uv をインストールしました"
}

install_ccexport() {
    ensure_uv || return 1
    info "ccexport をインストール中..."
    uv tool install --force "git+https://github.com/yosagi/ccexport.git"
    info "ccexport: $(which ccexport)"
}

install_osc_tap() {
    ensure_uv || return 1
    info "osc-tap をインストール中..."
    uv tool install --force "git+https://github.com/yosagi/osc-tap.git"
    info "osc-tap: $(which osc-tap)"
}

# --- メイン処理 ---

echo "========================================"
echo " Claude Code Kit ブートストラップ"
echo "========================================"
echo ""
echo "OS: $OS ($(uname -s))"
echo ""

# Step 1: 依存ツール
echo "--- Step 1: 依存ツールの確認・インストール ---"
echo ""

install_jq

# ccexport と osc-tap は任意だが、あると便利なので入れる
install_ccexport || warn "ccexport のインストールに失敗しました（セッションログエクスポートは使えません）"
install_osc_tap  || warn "osc-tap のインストールに失敗しました（ステータスライン表示は使えません）"

echo ""

# uv tool でインストールしたものが PATH に通っていない場合があるので再確認
export PATH="$HOME/.local/bin:$PATH"

# Step 2: グローバル設定
echo "--- Step 2: グローバル設定のインストール ---"
echo ""

"$SCRIPT_DIR/setup_global.sh" --install

echo ""
echo "========================================"
echo " ブートストラップ完了"
echo "========================================"
echo ""
echo "次のステップ:"
echo "  1. プロジェクトディレクトリに移動"
echo "     cd /path/to/your/project"
echo ""
echo "  2. ワークフロー定義をコピー"
echo "     cp $SCRIPT_DIR/CLAUDE.md ."
echo "     cp $SCRIPT_DIR/CLAUDE.local.md ."
echo ""
echo "  3. Claude Code を起動して人格セットアップ"
echo "     claude"
echo ""
