#!/bin/bash
# 目的: Ubuntu 26.04 以降で Claude Code の Bash sandbox（bubblewrap）が起動しない問題の手当て。
#       apparmor が既定で読み込む bwrap-userns-restrict プロファイルは bwrap の子プロセスを
#       unpriv_bwrap に落として全能力を奪うため、bwrap の中でもう一段 userns を作る
#       Claude Code の sandbox が EPERM で即死する。local override で子を bwrap プロファイルに
#       留めることで回避する。非該当環境（24.04 以前・他ディストロ・AppArmor 無効）では何もしない
# 関連: bootstrap.sh（新PC セットアップ時に呼ぶ）、setup_global.sh（~/.claude/scripts/ に配置する）、
#       claude-code issue #87680、bootc-dev/actions PR #55
# 前提: sudo が使えること（適用時のみ）。/etc/apparmor.d/local/ に書き、配布プロファイル本体は触らない
#
# 使い方:
#   ~/.claude/scripts/setup_bwrap_apparmor.sh            # 必要なら適用（sudo を求める）
#   ~/.claude/scripts/setup_bwrap_apparmor.sh --dry-run  # 何が起きるかだけ表示
#   ~/.claude/scripts/setup_bwrap_apparmor.sh --status   # 状態のみ（適用不要 / 適用済み / 要適用）
#
# 終了コード: 0 = 適用不要または適用済み（適用に成功した場合を含む）、1 = 要適用（--status / --dry-run）
#             または適用に失敗、2 = 引数エラー
#
# 症状: sandbox 内のどのコマンドでも
#   apply-seccomp: write /proc/self/setgroups (nested userns is capability-restricted; ...): Permission denied
# カーネルログ: apparmor="DENIED" operation="capable" profile="unpriv_bwrap" capname="sys_admin"
#
# 効かない手（採用しないこと）:
#   - local/unpriv_bwrap に priority 付き capability 規則: apparmor 5.0.2 では capability に priority が効かない
#   - 公式ドキュメントの profile bwrap /usr/bin/bwrap flags=(unconfined): 26.04 では配布プロファイルと衝突する
#   - bwrap を別パスにコピーして sandbox.bwrapPath で指す: パッケージ更新に追随しない

set -euo pipefail

# テスト用に差し替え可能（通常は触らない）
APPARMOR_D="${APPARMOR_D:-/etc/apparmor.d}"
APPARMOR_ENABLED_FILE="${APPARMOR_ENABLED_FILE:-/sys/module/apparmor/parameters/enabled}"
SUDO="${SUDO-sudo}"
BWRAP="${BWRAP:-bwrap}"
APPARMOR_PARSER="${APPARMOR_PARSER:-apparmor_parser}"

PROFILE="$APPARMOR_D/bwrap-userns-restrict"
LOCAL_OVERRIDE="$APPARMOR_D/local/bwrap-userns-restrict"

# 追記する規則。priority は同じパスの低優先権限を丸ごと置き換えるため、
# ix だけ書くと /** の rw が消える。rwlkm の行は必須
REQUIRED_RULES=(
    "priority=100 allow file rwlkm /**,"
    "priority=100 allow ix /**,"
)
OVERRIDE_HEADER="# bwrap の子を unpriv_bwrap に落とさず bwrap プロファイルに留める
# （Claude Code の sandbox など、bwrap 内で nested userns を使うものが動くように）
# claude-code-kit: setup_bwrap_apparmor.sh が配置。パッケージ更新でも保全される"

MODE="apply"
for arg in "$@"; do
    case "$arg" in
        --dry-run) MODE="dry-run" ;;
        --status)  MODE="status" ;;
        -h|--help) sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "不明なオプション: $arg" >&2; exit 2 ;;
    esac
done

GREEN='\033[0;32m'; YELLOW='\033[0;33m'; RED='\033[0;31m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }

# --- 判定 ---

# 0 = 適用不要（理由を stdout）、1 = 適用済み、2 = 要適用
classify() {
    if [[ "$(uname -s)" != "Linux" ]]; then
        echo "Linux ではない"; return 0
    fi
    if [[ ! -r "$APPARMOR_ENABLED_FILE" ]] || [[ "$(cat "$APPARMOR_ENABLED_FILE")" != "Y" ]]; then
        echo "AppArmor が無効"; return 0
    fi
    if [[ ! -f "$PROFILE" ]]; then
        echo "配布プロファイル $PROFILE が無い（24.04 以前や他ディストロ）"; return 0
    fi
    if has_required_rules; then
        return 1
    fi
    return 2
}

# local override に必要な 2 行が（コメントを除いて）揃っているか
has_required_rules() {
    [[ -f "$LOCAL_OVERRIDE" ]] || return 1
    local rule
    for rule in "${REQUIRED_RULES[@]}"; do
        grep -v '^[[:space:]]*#' "$LOCAL_OVERRIDE" | grep -qxF "$rule" || return 1
    done
    return 0
}

# nested userns が実際に成立するか（bwrap があるときだけ）。
# sandbox が死ぬのは bwrap 内で setgroups を書く操作なので、同じ操作を bwrap 越しに試す。
# 0 = 成立、1 = 不成立、2 = 検証手段なし
verify_nested_userns() {
    command -v "$BWRAP" >/dev/null 2>&1 || return 2
    command -v unshare >/dev/null 2>&1 || return 2
    local out
    if out=$("$BWRAP" --ro-bind / / --proc /proc --dev /dev --unshare-user --unshare-pid \
                 unshare -Ur cat /proc/self/setgroups 2>&1) && [[ "$out" == "deny" ]]; then
        return 0
    fi
    return 1
}

report_verification() {
    local rc=0
    verify_nested_userns || rc=$?
    case "$rc" in
        0) info "検証: bwrap 内の nested userns が成立（sandbox は動く）" ;;
        1) warn "検証: bwrap 内の nested userns が成立しない。カーネルログ（journalctl -k | grep apparmor）を確認してください"; return 1 ;;
        2) info "検証: bwrap または unshare が無いため実測は省略" ;;
    esac
}

# --- 適用 ---

apply_override() {
    local content
    if [[ -f "$LOCAL_OVERRIDE" ]]; then
        info "$LOCAL_OVERRIDE に追記します（既存の内容は保持）"
        content=$'\n'"$OVERRIDE_HEADER"
    else
        info "$LOCAL_OVERRIDE を作成します"
        content="$OVERRIDE_HEADER"
    fi
    local rule
    for rule in "${REQUIRED_RULES[@]}"; do
        content+=$'\n'"$rule"
    done

    printf '%s\n' "$content" | $SUDO tee -a "$LOCAL_OVERRIDE" >/dev/null

    info "プロファイルを検査中: $APPARMOR_PARSER -Q"
    if ! $SUDO "$APPARMOR_PARSER" -Q "$PROFILE"; then
        error "プロファイルの検査に失敗しました。$LOCAL_OVERRIDE を確認してください"
        return 1
    fi
    info "プロファイルを再読込中: $APPARMOR_PARSER -r"
    if ! $SUDO "$APPARMOR_PARSER" -r "$PROFILE"; then
        error "プロファイルの再読込に失敗しました"
        return 1
    fi
    info "適用しました"
}

# --- メイン ---

reason=""
state=0
reason=$(classify) || state=$?

case "$state" in
    0)
        info "適用不要: $reason"
        exit 0
        ;;
    1)
        info "適用済み: $LOCAL_OVERRIDE に必要な規則があります"
        [[ "$MODE" == "status" ]] && exit 0
        report_verification || exit 1
        exit 0
        ;;
esac

# state == 2: 要適用
case "$MODE" in
    status)
        warn "要適用: $PROFILE が有効で、$LOCAL_OVERRIDE に必要な規則がありません"
        exit 1
        ;;
    dry-run)
        warn "要適用: $PROFILE が有効で、$LOCAL_OVERRIDE に必要な規則がありません"
        echo "実行時は以下を行います:"
        echo "  1. $LOCAL_OVERRIDE に追記（sudo）:"
        printf '       %s\n' "${REQUIRED_RULES[@]}"
        echo "  2. sudo $APPARMOR_PARSER -Q $PROFILE   （検査）"
        echo "  3. sudo $APPARMOR_PARSER -r $PROFILE   （再読込）"
        exit 1
        ;;
    apply)
        info "要適用: Ubuntu 26.04 以降の bwrap-userns-restrict プロファイルが有効です"
        apply_override || exit 1
        report_verification || exit 1
        exit 0
        ;;
esac
