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
EXTRAS_DIR="$REGISTRY_DIR/dist-extras"
EXTRAS_STAMP_DIR="$CLAUDE_DIR/extras-stamps"

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
  - グローバル KB コンテキスト組み立てスクリプト (build_startup_context.py)

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

## dist-extras（キット外の配布経路）
# ~/Notes/claude-registry/dist-extras/<route>/ を規約に従って処理する。
#   skills/<name>/   スキル本体
#   deprecated       廃止スキル名を1行1件（`# 以降`はコメント）
#   .extras-stamp    経路ごとの更新印
# キットは規約だけを知り、中身には関知しない。

# deprecated ファイルからスキル名を読み出す（コメント・空行を除去）
read_deprecated_names() {
    local file="$1"
    [[ -f "$file" ]] || return 0
    sed -e 's/#.*//' -e 's/[[:space:]]//g' "$file" | grep -v '^$' || true
}

install_extras() {
    [[ -d "$EXTRAS_DIR" ]] || return 0

    local route_dir route name skill_dir found=0
    for route_dir in "$EXTRAS_DIR"/*/; do
        [[ -d "$route_dir" ]] || continue
        route=$(basename "$route_dir")

        if [[ $found -eq 0 ]]; then
            echo ""
            info "extras をインストール中..."
            found=1
        fi
        info "  経路: $route"

        # 墓標の処理はインストールより先に行う
        # （同名スキルが復活した場合にインストール側が勝つようにするため）
        while read -r name; do
            "$SCRIPT_DIR/install-skill.sh" --uninstall "$name"
        done < <(read_deprecated_names "$route_dir/deprecated")

        for skill_dir in "$route_dir"skills/*/; do
            if [[ -d "$skill_dir" ]]; then
                "$SCRIPT_DIR/install-skill.sh" "$skill_dir"
            fi
        done

        # ローカル stamp を更新（wrapper の auto-install 判定に使う）
        if [[ -f "$route_dir/.extras-stamp" ]]; then
            mkdir -p "$EXTRAS_STAMP_DIR"
            cp "$route_dir/.extras-stamp" "$EXTRAS_STAMP_DIR/$route"
        fi
    done
}

uninstall_extras() {
    [[ -d "$EXTRAS_DIR" ]] || return 0

    local route_dir skill_dir name
    for route_dir in "$EXTRAS_DIR"/*/; do
        [[ -d "$route_dir" ]] || continue
        for skill_dir in "$route_dir"skills/*/; do
            if [[ -d "$skill_dir" ]]; then
                name=$(basename "$skill_dir")
                if [[ -d "$SKILLS_DIR/$name" ]]; then
                    "$SCRIPT_DIR/install-skill.sh" --uninstall "$name"
                fi
            fi
        done
    done
    rm -rf "$EXTRAS_STAMP_DIR"
}

status_extras() {
    [[ -d "$EXTRAS_DIR" ]] || return 0

    local route_dir route skill_dir name found=0
    for route_dir in "$EXTRAS_DIR"/*/; do
        [[ -d "$route_dir" ]] || continue
        route=$(basename "$route_dir")

        if [[ $found -eq 0 ]]; then
            echo ""
            echo "Extras:"
            found=1
        fi
        echo "  [$route]"

        for skill_dir in "$route_dir"skills/*/; do
            if [[ -d "$skill_dir" ]]; then
                name=$(basename "$skill_dir")
                if [[ -d "$SKILLS_DIR/$name" ]]; then
                    echo "    ✓ $name"
                else
                    echo "    ✗ $name (未インストール)"
                fi
            fi
        done
    done
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

    # 1b. extras（キット外の配布経路）をインストール
    install_extras

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
    cp "$SCRIPT_DIR/global.claude/hooks/backup_project_state.sh" "$HOOKS_DIR/"
    chmod +x "$HOOKS_DIR/backup_project_state.sh"

    info "SessionStart hook をインストール中..."
    cp "$SCRIPT_DIR/global.claude/hooks/session_start.sh" "$HOOKS_DIR/"
    chmod +x "$HOOKS_DIR/session_start.sh"

    info "Time awareness hook をインストール中..."
    cp "$SCRIPT_DIR/global.claude/hooks/time_awareness.sh" "$HOOKS_DIR/"
    chmod +x "$HOOKS_DIR/time_awareness.sh"

    # 3. statusline.sh をコピー
    info "Status Line をインストール中..."
    cp "$SCRIPT_DIR/global.claude/statusline.sh" "$CLAUDE_DIR/"
    chmod +x "$CLAUDE_DIR/statusline.sh"

    # 4. claude-code ラッパーをインストール（osc-tap がある場合のみ）
    if command -v osc-tap >/dev/null 2>&1; then
        info "claude-code ラッパーをインストール中..."
        mkdir -p "$BIN_DIR"
        # 実行中の wrapper 自身（auto-install 経由）を上書きする可能性があるため
        # atomic に置き換える。cp は同一 inode を truncate するので実行中の bash が
        # 壊れるが、mv (rename) なら旧 inode が残り実行中プロセスは影響を受けない。
        local tmp_wrapper="$BIN_DIR/.claude-code.tmp.$$"
        cp "$SCRIPT_DIR/scripts/claude-code" "$tmp_wrapper"
        chmod +x "$tmp_wrapper"
        mv -f "$tmp_wrapper" "$BIN_DIR/claude-code"
    else
        warn "osc-tap 未インストールのため claude-code ラッパーはスキップしました"
    fi

    # 5. build_startup_context.py をインストール
    info "build_startup_context.py をインストール中..."
    mkdir -p "$CLAUDE_DIR/scripts"
    cp "$SCRIPT_DIR/scripts/build_startup_context.py" "$CLAUDE_DIR/scripts/"

    # 6. グローバルルール移行チェック
    # global_rules.md はグローバル KB (registry/<host>/kb/) に統合済み。
    # 旧ファイルが残っていたら案内を出す。
    if [[ -f "$GLOBAL_RULES_FILE" ]]; then
        warn "旧 global_rules.md が残っています: $GLOBAL_RULES_FILE"
        warn "グローバル KB に統合済みです。削除してください: rm $GLOBAL_RULES_FILE"
    fi
    if [[ -f "$GLOBAL_CLAUDE_MD" ]] && grep -q '@.*global_rules' "$GLOBAL_CLAUDE_MD" 2>/dev/null; then
        info "~/.claude/CLAUDE.md から旧インクルード行を除去中..."
        sed -i '/@.*global_rules/d' "$GLOBAL_CLAUDE_MD"
    fi

    # 7. settings.json を編集
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
        "Edit(/reports/jobs/**)"
    ]'

    # 無効な Write(path) ルールの掃除
    # 2026-07-15 に dist から Write(path) 7行を削除したが、下のマージは追加のみで
    # 削除が伝播しないため、ここで明示的に除去する。パスパターン付き Write(...) は
    # ファイル権限チェックに一切マッチしない（実測済み、起動時警告の原因になるだけ）ので
    # 除去しても挙動は変わらない。bare "Write"（パスなし）は有効なルールなので残す
    local stale_write_rules
    stale_write_rules=$(jq -r '[.permissions.allow // [] | .[] | select(type == "string" and startswith("Write("))] | .[]' "$SETTINGS_FILE")
    if [[ -n "$stale_write_rules" ]]; then
        info "無効な Write(path) ルールを除去します（起動時警告の原因）:"
        echo "$stale_write_rules" | sed 's/^/    - /'
    fi

    # settings.json を更新
    local tmp=$(mktemp)
    jq --argjson perms "$permissions" \
       --arg hook_end_cmd "$HOOKS_DIR/session_end.sh" \
       --arg hook_memory_cmd "$HOOKS_DIR/process_memory_drafts.sh" \
       --arg hook_start_cmd "$HOOKS_DIR/session_start.sh" \
       --arg hook_time_cmd "$HOOKS_DIR/time_awareness.sh" \
       --arg statusline_cmd "$CLAUDE_DIR/statusline.sh" '
        # 許可設定をマージ（無効な Write(path) ルールは除去）
        .permissions.allow = (
            ((.permissions.allow // []) | map(select((type == "string" and startswith("Write(")) | not)))
            + $perms | unique
        ) |
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
        # UserPromptSubmit hook をマージ（時報: time_awareness.sh）
        .hooks.UserPromptSubmit = (
            [.hooks.UserPromptSubmit // [] | .[] | select(.hooks[0].command != $hook_time_cmd)] +
            [{"hooks": [{"type": "command", "command": $hook_time_cmd}]}]
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

    # extras のスキルを削除
    uninstall_extras

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

    # extras
    status_extras

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
