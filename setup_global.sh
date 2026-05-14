#!/bin/bash
# 目的: Claude Code のグローバル設定を一括でセットアップする
# 関連: README.md
# 前提: jq がインストールされていること

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CLAUDE_DIR="$HOME/.claude"
SETTINGS_FILE="$CLAUDE_DIR/settings.json"
HOOKS_DIR="$CLAUDE_DIR/hooks"
SKILLS_DIR="$CLAUDE_DIR/skills"
BIN_DIR="$HOME/.local/bin"
SESSION_LOG_DIR="$HOME/Notes/journals/claude_sessions"
REGISTRY_DIR="$HOME/Notes/claude-registry"
GLOBAL_RULES_FILE="$REGISTRY_DIR/global_rules.md"
GLOBAL_CLAUDE_MD="$CLAUDE_DIR/CLAUDE.md"

# 色付き出力
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }

show_help() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Claude Code グローバル設定の一括セットアップ

Options:
  --install     グローバル設定をインストール
  --uninstall   グローバル設定をアンインストール
  --status      インストール状態を確認
  --help        このヘルプを表示

インストール内容:
  - Skills (dist/global.claude/skills/ 内の全スキル)
  - Sandbox 例外設定 (スクリプトを含むスキルの excludedCommands)
  - SessionEnd hook (セッション終了時のログエクスポート)
  - Status Line (コンテキスト残量表示)
  - 許可設定 (記憶ファイルへのアクセス許可)
  - claude-code ラッパー (osc-tap 経由の起動スクリプト、osc-tap 必須)
  - グローバルルール (~/.claude/CLAUDE.md + registry/global_rules.md、初回のみ)

EOF
}

check_dependencies() {
    local missing=()
    command -v jq >/dev/null 2>&1 || missing+=("jq")

    if [[ ${#missing[@]} -gt 0 ]]; then
        error "以下のコマンドが必要です: ${missing[*]}"
        return 1
    fi

    # ccexport は警告のみ（なくても基本機能は動く）
    if ! command -v ccexport >/dev/null 2>&1; then
        warn "ccexport が見つかりません。セッションログエクスポート機能は動作しません。"
        warn "  pipx install git+https://github.com/yosagi/ccexport.git"
    fi

    # osc-tap は警告のみ（なくてもインストールは進む）
    if ! command -v osc-tap >/dev/null 2>&1; then
        warn "osc-tap が見つかりません。claude-code ラッパーはインストールされません。"
        warn "  pipx install git+https://github.com/yosagi/osc-tap.git"
    fi
}

## 廃止されたスキルのブラックリスト
# リネーム・統合等で不要になったスキル。インストール済みなら削除を案内する。
DEPRECATED_SKILLS=(
    "inbox-dispatch"  # inbox-send に統合 (2026-02-19)
)

check_deprecated_skills() {
    local found=0
    for skill in "${DEPRECATED_SKILLS[@]}"; do
        if [[ -d "$SKILLS_DIR/$skill" ]]; then
            if [[ $found -eq 0 ]]; then
                echo ""
                warn "廃止されたスキルがインストールされています:"
                found=1
            fi
            warn "  - $skill → 手動で削除してください: rm -rf $SKILLS_DIR/$skill"
        fi
    done
    if [[ $found -eq 1 ]]; then
        echo ""
    fi
}

do_install() {
    echo "Claude Code グローバル設定をインストールします..."
    echo ""

    # settings.json のバックアップ
    if [[ -f "$SETTINGS_FILE" ]]; then
        local backup="${SETTINGS_FILE}.bak.$(date +%Y%m%d_%H%M%S)"
        cp "$SETTINGS_FILE" "$backup"
        info "settings.json をバックアップ: $backup"
    fi

    # 依存関係チェック
    check_dependencies || exit 1

    # ディレクトリ作成
    mkdir -p "$CLAUDE_DIR"
    mkdir -p "$HOOKS_DIR"
    mkdir -p "$SKILLS_DIR"
    mkdir -p "$SESSION_LOG_DIR"

    # 1. Skills をインストール（install-skill.sh に委譲）
    info "Skills をインストール中..."
    for skill_dir in "$SCRIPT_DIR/global.claude/skills"/*/; do
        if [[ -d "$skill_dir" ]]; then
            "$SCRIPT_DIR/install-skill.sh" "$skill_dir"
        fi
    done

    # 廃止スキルのチェック
    check_deprecated_skills

    # 2. hooks をコピー
    info "SessionEnd hook をインストール中..."
    cp "$SCRIPT_DIR/global.claude/hooks/session_end.sh" "$HOOKS_DIR/"
    chmod +x "$HOOKS_DIR/session_end.sh"
    cp "$SCRIPT_DIR/global.claude/hooks/process_journal_drafts.sh" "$HOOKS_DIR/"
    chmod +x "$HOOKS_DIR/process_journal_drafts.sh"
    cp "$SCRIPT_DIR/global.claude/hooks/process_memory_drafts.sh" "$HOOKS_DIR/"
    chmod +x "$HOOKS_DIR/process_memory_drafts.sh"
    cp "$SCRIPT_DIR/global.claude/hooks/append_memory_entry.py" "$HOOKS_DIR/"
    chmod +x "$HOOKS_DIR/append_memory_entry.py"

    info "SessionStart hook をインストール中..."
    cp "$SCRIPT_DIR/global.claude/hooks/session_start.sh" "$HOOKS_DIR/"
    chmod +x "$HOOKS_DIR/session_start.sh"

    # 3. statusline.sh をコピー
    info "Status Line をインストール中..."
    cp "$SCRIPT_DIR/global.claude/statusline.sh" "$CLAUDE_DIR/"
    chmod +x "$CLAUDE_DIR/statusline.sh"

    # 4. claude-code ラッパーをインストール（osc-tap がある場合のみ）
    if command -v osc-tap >/dev/null 2>&1; then
        info "claude-code ラッパーをインストール中..."
        mkdir -p "$BIN_DIR"
        cp "$SCRIPT_DIR/scripts/claude-code" "$BIN_DIR/"
        chmod +x "$BIN_DIR/claude-code"
    else
        warn "osc-tap 未インストールのため claude-code ラッパーはスキップしました"
    fi

    # 5. グローバルルールをインストール（存在しない場合のみ）
    if [[ ! -f "$GLOBAL_RULES_FILE" ]]; then
        info "グローバルルールを配置中..."
        mkdir -p "$REGISTRY_DIR"
        cp "$SCRIPT_DIR/global.claude/global_rules.md" "$GLOBAL_RULES_FILE"
    else
        info "グローバルルール: 既存ファイルを維持 ($GLOBAL_RULES_FILE)"
    fi
    if [[ ! -f "$GLOBAL_CLAUDE_MD" ]]; then
        info "~/.claude/CLAUDE.md を作成中..."
        echo "@$GLOBAL_RULES_FILE" > "$GLOBAL_CLAUDE_MD"
    else
        info "~/.claude/CLAUDE.md: 既存ファイルを維持"
    fi

    # 6. settings.json を編集
    info "settings.json を編集中..."

    if [[ ! -f "$SETTINGS_FILE" ]]; then
        echo '{}' > "$SETTINGS_FILE"
    fi

    # 許可設定
    # パスは / prefix でプロジェクトルート相対（cwd がサブディレクトリでも有効）
    local permissions='[
        "Read(/reports/memory/**)",
        "Read(/reports/personas/**)",
        "Read(/work_in_progress.md)",
        "Read(/reports/ideas/**)",
        "Read(/reports/todos/**)",
        "Read(/reports/insight/**)",
        "Read(/reports/jobs/**)",
        "Read(~/work/*/reports/**)",
        "Edit(/reports/memory/**)",
        "Edit(/reports/personas/**)",
        "Edit(/work_in_progress.md)",
        "Edit(/reports/ideas/**)",
        "Edit(/reports/todos/**)",
        "Edit(/reports/insight/**)",
        "Edit(/reports/jobs/**)",
        "Write(/reports/memory/**)",
        "Write(/reports/personas/**)",
        "Write(/work_in_progress.md)",
        "Write(/reports/ideas/**)",
        "Write(/reports/todos/**)",
        "Write(/reports/insight/**)",
        "Write(/reports/jobs/**)"
    ]'

    # settings.json を更新
    local tmp=$(mktemp)
    jq --argjson perms "$permissions" \
       --arg hook_end_cmd "$HOOKS_DIR/session_end.sh" \
       --arg hook_memory_cmd "$HOOKS_DIR/process_memory_drafts.sh" \
       --arg hook_start_cmd "$HOOKS_DIR/session_start.sh" \
       --arg statusline_cmd "$CLAUDE_DIR/statusline.sh" '
        # 許可設定をマージ
        .permissions.allow = ((.permissions.allow // []) + $perms | unique) |
        # SessionEnd hook をマージ（既存エントリを保持、自分の hook は追加/更新）
        .hooks.SessionEnd = (
            [.hooks.SessionEnd // [] | .[] | select(
                .hooks[0].command != $hook_end_cmd and
                .hooks[0].command != $hook_memory_cmd
            )] +
            [{"hooks": [{"type": "command", "command": $hook_end_cmd}]},
             {"hooks": [{"type": "command", "command": $hook_memory_cmd}]}]
        ) |
        # SessionStart hook をマージ（既存エントリを保持、自分の hook は追加/更新）
        .hooks.SessionStart = (
            [.hooks.SessionStart // [] | .[] | select(.hooks[0].command != $hook_start_cmd)] +
            [{"hooks": [{"type": "command", "command": $hook_start_cmd}]}]
        ) |
        # Status Line を設定
        .statusLine = {
            "type": "command",
            "command": $statusline_cmd
        }
    ' "$SETTINGS_FILE" > "$tmp" && mv "$tmp" "$SETTINGS_FILE"

    echo ""
    info "インストール完了！"
    echo ""
    echo "セッションログ出力先: $SESSION_LOG_DIR"
    echo ""
    echo "注意: 新しいセッションを開始すると設定が反映されます。"
}

do_uninstall() {
    echo "Claude Code グローバル設定をアンインストールします..."
    echo ""

    # Skills を削除
    info "Skills を削除中..."
    for skill_dir in "$SCRIPT_DIR/global.claude/skills"/*/; do
        skill=$(basename "$skill_dir")
        if [[ -d "$SKILLS_DIR/$skill" ]]; then
            rm -rf "$SKILLS_DIR/$skill"
            info "  - $skill"
        fi
    done

    # hooks を削除
    if [[ -f "$HOOKS_DIR/session_end.sh" ]]; then
        info "SessionEnd hook を削除中..."
        rm "$HOOKS_DIR/session_end.sh"
    fi
    if [[ -f "$HOOKS_DIR/process_journal_drafts.sh" ]]; then
        rm "$HOOKS_DIR/process_journal_drafts.sh"
    fi
    if [[ -f "$HOOKS_DIR/session_start.sh" ]]; then
        info "SessionStart hook を削除中..."
        rm "$HOOKS_DIR/session_start.sh"
    fi

    # statusline.sh を削除
    if [[ -f "$CLAUDE_DIR/statusline.sh" ]]; then
        info "Status Line を削除中..."
        rm "$CLAUDE_DIR/statusline.sh"
    fi

    # claude-code ラッパーを削除
    if [[ -f "$BIN_DIR/claude-code" ]]; then
        info "claude-code ラッパーを削除中..."
        rm "$BIN_DIR/claude-code"
    fi

    # settings.json から関連設定を削除
    if [[ -f "$SETTINGS_FILE" ]]; then
        info "settings.json を編集中..."
        local tmp=$(mktemp)
        jq '
            del(.hooks.SessionEnd) |
            del(.hooks.SessionStart) |
            del(.statusLine) |
            if .hooks == {} then del(.hooks) else . end
        ' "$SETTINGS_FILE" > "$tmp" && mv "$tmp" "$SETTINGS_FILE"
        # 許可設定は残す（他の用途で使っている可能性があるため）
        warn "許可設定 (permissions.allow) は残しています"
    fi

    echo ""
    info "アンインストール完了！"
}

do_status() {
    echo "Claude Code グローバル設定の状態:"
    echo ""

    # Skills
    echo "Skills:"
    for skill_dir in "$SCRIPT_DIR/global.claude/skills"/*/; do
        skill=$(basename "$skill_dir")
        if [[ -d "$SKILLS_DIR/$skill" ]]; then
            echo "  ✓ $skill"
        else
            echo "  ✗ $skill (未インストール)"
        fi
    done

    # hooks
    echo ""
    echo "Hooks:"
    if [[ -f "$HOOKS_DIR/session_end.sh" ]]; then
        echo "  ✓ session_end.sh"
    else
        echo "  ✗ session_end.sh (未インストール)"
    fi
    if [[ -f "$HOOKS_DIR/session_start.sh" ]]; then
        echo "  ✓ session_start.sh"
    else
        echo "  ✗ session_start.sh (未インストール)"
    fi

    # statusline
    echo ""
    echo "Status Line:"
    if [[ -f "$CLAUDE_DIR/statusline.sh" ]]; then
        echo "  ✓ statusline.sh"
    else
        echo "  ✗ statusline.sh (未インストール)"
    fi

    # claude-code ラッパー
    echo ""
    echo "claude-code ラッパー:"
    if [[ -f "$BIN_DIR/claude-code" ]]; then
        echo "  ✓ $BIN_DIR/claude-code"
    else
        echo "  ✗ claude-code (未インストール)"
    fi

    # settings.json
    echo ""
    echo "settings.json:"
    if [[ -f "$SETTINGS_FILE" ]]; then
        if jq -e '.hooks.SessionEnd' "$SETTINGS_FILE" >/dev/null 2>&1; then
            echo "  ✓ SessionEnd hook 設定あり"
        else
            echo "  ✗ SessionEnd hook 設定なし"
        fi
        if jq -e '.statusLine' "$SETTINGS_FILE" >/dev/null 2>&1; then
            echo "  ✓ statusLine 設定あり"
        else
            echo "  ✗ statusLine 設定なし"
        fi
        local perm_count=$(jq '.permissions.allow | length' "$SETTINGS_FILE" 2>/dev/null || echo "0")
        echo "  許可設定: $perm_count 件"
    else
        echo "  ✗ settings.json が存在しません"
    fi

    # グローバルルール
    echo ""
    echo "グローバルルール:"
    if [[ -f "$GLOBAL_CLAUDE_MD" ]]; then
        echo "  ✓ ~/.claude/CLAUDE.md"
    else
        echo "  ✗ ~/.claude/CLAUDE.md (未作成)"
    fi
    if [[ -f "$GLOBAL_RULES_FILE" ]]; then
        echo "  ✓ $GLOBAL_RULES_FILE"
    else
        echo "  ✗ $GLOBAL_RULES_FILE (未作成)"
    fi

    # 依存関係
    echo ""
    echo "依存関係:"
    if command -v jq >/dev/null 2>&1; then
        echo "  ✓ jq: $(which jq)"
    else
        echo "  ✗ jq: 未インストール"
    fi
    if command -v ccexport >/dev/null 2>&1; then
        echo "  ✓ ccexport: $(which ccexport)"
    else
        echo "  ✗ ccexport: 未インストール (セッションログエクスポート不可)"
    fi
    if command -v osc-tap >/dev/null 2>&1; then
        echo "  ✓ osc-tap: $(which osc-tap)"
    else
        echo "  ✗ osc-tap: 未インストール (claude-code ラッパー不可)"
    fi

    # sessions ディレクトリ
    echo ""
    if [[ -d "$SESSION_LOG_DIR" ]]; then
        local count=$(ls -1 "$SESSION_LOG_DIR" 2>/dev/null | wc -l)
        echo "セッションログ: $SESSION_LOG_DIR ($count ファイル)"
    else
        echo "セッションログ: $SESSION_LOG_DIR (未作成)"
    fi

    # 廃止スキルのチェック
    check_deprecated_skills
}

# メイン処理
case "${1:-}" in
    --install)
        do_install
        ;;
    --uninstall)
        do_uninstall
        ;;
    --status)
        do_status
        ;;
    --help|-h)
        show_help
        ;;
    *)
        show_help
        exit 1
        ;;
esac
