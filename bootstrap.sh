#!/bin/bash
# 目的: 新PCの初期セットアップ（claude 本体確認 + 依存ツール導入 + グローバル設定インストール）
# 関連: setup_global.sh, update-registry.sh, README.md
# 前提: git, curl が使えること。claude 本体がインストール済みであること（未導入なら案内して終了）。
#       registry 同期済みPCでは ~/Notes/claude-registry/dist/bootstrap.sh を、
#       それ以外では clone した本スクリプトを実行する（最後に update-registry.sh で registry に配置）。
#       sudo が使えること（jq 導入時）。

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

REGISTRY_DIST="$HOME/Notes/claude-registry/dist"

# registry 内のコピーから実行されているか（同期済み新PCのセットアップ経路）
in_registry() {
    [[ "$SCRIPT_DIR" == "$(cd "$REGISTRY_DIST" 2>/dev/null && pwd)" ]]
}

# --- Step 0: claude 本体の確認 ---

check_claude() {
    if command -v claude >/dev/null 2>&1; then
        info "claude: $(command -v claude) (インストール済み)"
        return 0
    fi

    error "Claude Code 本体（claude）が見つかりません。"
    echo ""
    echo "先に native 版をインストールしてください（npm 管理は非推奨）:"
    echo ""
    echo "  curl -fsSL https://claude.ai/install.sh | bash"
    echo ""
    echo "インストール後、このスクリプトを再実行してください。"
    exit 1
}

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

# Step 0: claude 本体
echo "--- Step 0: Claude Code 本体の確認 ---"
echo ""

check_claude

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

if in_registry; then
    # 同期済み新PC: registry のコピーからそのまま install
    "$SCRIPT_DIR/setup_global.sh" --install
else
    # clone から: registry に配置してから registry のコピーで install
    # （update-registry.sh が rsync + stamp 更新 + install を行う）
    "$SCRIPT_DIR/update-registry.sh"
fi

echo ""
echo "========================================"
echo " ブートストラップ完了"
echo "========================================"
echo ""
echo "次のステップ:"
echo "  1. プロジェクトディレクトリに移動"
echo "     cd /path/to/your/project"
echo ""
echo "  2. claude-code で起動（CLAUDE.md / CLAUDE.local.md は自動配置されます）"
echo "     claude-code"
echo ""
echo "  3. 初回起動時に人格セットアップ（/persona-setup）"
echo ""
if ! in_registry; then
    echo "キットの更新:"
    echo "  cd $SCRIPT_DIR && git pull && ./update-registry.sh"
    echo ""
fi
