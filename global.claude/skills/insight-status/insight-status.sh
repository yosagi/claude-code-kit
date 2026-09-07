#!/usr/bin/env bash
# insight-status.sh — 定期 insight の状況を読み取り専用で報告する
#
# 使い方: insight-status.sh [プロジェクトルート]
#   省略時は CLAUDE_PROJECT_DIR → カレントディレクトリの順で決める
#
# 見るもの（すべて読み取り専用。systemctl は D-Bus が要るため使わず、
# timer unit ファイルと journalctl から取る）:
#   - ~/.config/systemd/user/insight-<unit>.timer   定期実行の有無・スケジュール
#   - journalctl --user -u insight-<unit>.service    前回の発火・完了・Phase 0 スキップ
#   - reports/insight/*_insight.md                    最新レポート・未レビュー（## Review 結果 の有無）
#   - reports/inbox/INDEX.md                          from_insight の [NEW]
#   - reports/jobs/                                   ローカルジョブ件数
#
# 出力は markdown。exit code は常に 0（情報提供のみ）。

set -uo pipefail

UNIT_PREFIX="insight"
SYSTEMD_DIR="$HOME/.config/systemd/user"

project="${1:-${CLAUDE_PROJECT_DIR:-$PWD}}"
project="${project/#\~/$HOME}"
project="${project%/}"
if [[ ! -d "$project" ]]; then
    echo "insight-status: プロジェクトディレクトリが見つかりません: $project" >&2
    exit 0
fi

# insight-schedule.sh の path_to_unit_name と同じ変換
path_to_unit_name() {
    local name="${1#"$HOME/"}"
    name="${name//\//-}"
    name="${name//./-}"
    echo "$name"
}

unit_name="$(path_to_unit_name "$project")"
timer_file="$SYSTEMD_DIR/${UNIT_PREFIX}-${unit_name}.timer"
service_unit="${UNIT_PREFIX}-${unit_name}.service"
insight_dir="$project/reports/insight"

echo "## insight の状況（$(basename "$project")）"
echo

# ---- insight を使っているか -------------------------------------------------
if [[ ! -f "$timer_file" && ! -d "$insight_dir" ]]; then
    echo "- insight は未使用（timer unit も reports/insight/ も無い）"
    exit 0
fi

# ---- スケジュール -----------------------------------------------------------
scheduled=0
on_calendar=""
if [[ -f "$timer_file" ]]; then
    scheduled=1
    on_calendar="$(sed -n 's/^OnCalendar=//p' "$timer_file" | head -1)"
    delay="$(sed -n 's/^RandomizedDelaySec=//p' "$timer_file" | head -1)"
    next_run=""
    if command -v systemd-analyze >/dev/null 2>&1 && [[ -n "$on_calendar" ]]; then
        next_run="$(systemd-analyze calendar "$on_calendar" 2>/dev/null \
            | sed -n 's/^ *Next elapse: *//p' | head -1)"
    fi
    line="- 定期実行: あり（\`$on_calendar\`"
    [[ -n "$delay" ]] && line+="、ランダム遅延 ${delay}s"
    line+="）"
    [[ -n "$next_run" ]] && line+="。次回 $next_run"
    echo "$line"
else
    echo "- 定期実行: なし（手動実行のみ。reports/insight/ は存在）"
fi

# ---- 前回の発火（journalctl） ----------------------------------------------
last_start=""
last_finish=""
journal_ok=0
skipped_phase0=0
if [[ $scheduled -eq 1 ]] && command -v journalctl >/dev/null 2>&1; then
    journal="$(journalctl --user -u "$service_unit" --no-pager -o short-iso 2>/dev/null || true)"
    if [[ -n "$journal" ]]; then
        journal_ok=1
        last_start="$(grep -E 'Starting Insight report' <<<"$journal" | tail -1 | cut -d' ' -f1)"
        last_finish="$(grep -E 'Finished Insight report|Failed to start|Deactivated' <<<"$journal" | tail -1 | cut -d' ' -f1)"
        if [[ -n "$last_start" ]]; then
            # 前回の発火以降の出力に Phase 0 スキップの文言があるか
            since_last="$(awk -v s="$last_start" '$1 >= s' <<<"$journal")"
            if grep -q -E 'Phase 0|スキップ|行いませんでした' <<<"$since_last"; then
                skipped_phase0=1
            fi
        fi
    fi
fi

# ---- レポート ---------------------------------------------------------------
latest_report=""
latest_report_date=""
unreviewed=()
if [[ -d "$insight_dir" ]]; then
    # レビュー済みの判定: レポート末尾に「## Review 結果」節がある、または
    # 同日付の insight 通知が reports/inbox/done/ に移動済み（Review 結果節が導入される前の運用）
    inbox_done="$project/reports/inbox/done"
    while IFS= read -r f; do
        [[ -n "$f" ]] || continue
        base="$(basename "$f")"
        d="${base%%_*}"
        if ! grep -q '^## Review 結果' "$f" \
           && ! ls "$inbox_done/${d}_from_insight"*.md >/dev/null 2>&1; then
            unreviewed+=("$base")
        fi
        latest_report="$base"
    done < <(ls "$insight_dir"/*_insight.md 2>/dev/null | sort)
    latest_report_date="${latest_report%%_*}"
fi

# ---- 前回発火とレポートの突き合わせ -----------------------------------------
if [[ $scheduled -eq 1 ]]; then
    if [[ $journal_ok -eq 0 ]]; then
        echo "- 前回の発火: 不明（journalctl が読めない）"
    elif [[ -z "$last_start" ]]; then
        echo "- 前回の発火: 記録なし（timer 登録後まだ一度も発火していないか、journal が回転済み）"
    else
        start_date="${last_start%%T*}"
        start_hm="$(cut -c12-16 <<<"$last_start")"
        if [[ -z "$last_finish" || "$last_finish" < "$last_start" ]]; then
            echo "- 前回の発火: $start_date $start_hm 開始、**完了記録なし**（走行中、または途中で停止）"
        else
            finish_hm="$(cut -c12-16 <<<"$last_finish")"
            verdict=""
            if [[ -n "$latest_report_date" && "$latest_report_date" == "$start_date" ]]; then
                verdict="レポート生成 \`$latest_report\`"
            elif [[ $skipped_phase0 -eq 1 ]]; then
                verdict="Phase 0 スキップ（活動なし、レポートなし）"
            else
                verdict="**レポートなし → 失敗の疑い**（journalctl --user -u $service_unit で確認）"
            fi
            echo "- 前回の発火: $start_date $start_hm → $finish_hm 完了。$verdict"
        fi
    fi
fi

# ---- 未レビュー・inbox -------------------------------------------------------
if [[ -n "$latest_report" ]]; then
    echo "- 最新レポート: \`reports/insight/$latest_report\`"
else
    echo "- レポート: まだ無い"
fi

if [[ ${#unreviewed[@]} -gt 0 ]]; then
    n=${#unreviewed[@]}
    if [[ $n -le 5 ]]; then
        shown="${unreviewed[*]}"
    else
        shown="${unreviewed[*]: -5}（ほか $((n-5)) 件）"
    fi
    echo "- 未レビュー: $n 件 — $shown → \`/insight-review\` で処理"
else
    echo "- 未レビュー: なし"
fi

index="$project/reports/inbox/INDEX.md"
if [[ -f "$index" ]]; then
    new_cnt="$(grep -c '\[NEW\].*from_insight' "$index" || true)"
    read_cnt="$(grep -E '^- [0-9]{4}-[0-9]{2}-[0-9]{2}_from_insight' "$index" | grep -vc '\[NEW\]' || true)"
    if [[ "${new_cnt:-0}" -gt 0 || "${read_cnt:-0}" -gt 0 ]]; then
        echo "- inbox の insight 通知: 未読 ${new_cnt:-0} 件、既読未完了 ${read_cnt:-0} 件"
    fi
fi

# ---- ローカルジョブ ---------------------------------------------------------
jobs_dir="$project/reports/jobs"
if [[ -d "$jobs_dir" ]]; then
    every_cnt="$(ls "$jobs_dir"/*_every_*.md 2>/dev/null | wc -l)"
    once_cnt="$(ls "$jobs_dir"/*_once_*.md 2>/dev/null | wc -l)"
    if [[ "$every_cnt" -gt 0 || "$once_cnt" -gt 0 ]]; then
        echo "- ローカルジョブ: every $every_cnt 件、once $once_cnt 件（未処理）"
    fi
fi

exit 0
