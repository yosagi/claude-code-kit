# statusline 部品: wezterm の User Variable を設定する（キーマップ制御用）。断片は出さない
# 枠組み statusline.sh から source される。
#
# /dev/tty 経由で端末にエスケープシーケンスを送る。
# Claude Code 2.1.139+ では statusLine command が制御端末なし (tty_nr=0) で
# 起動されるため /dev/tty が実際の端末に繋がらない。
# フォールバックとして親プロセスチェーンから実際の pty デバイスを探す。
# 親プロセスをたどるので、sinks/（setsid で切り離される）には置けない。

find_tty_device() {
    # /dev/tty が使えるか確認（制御端末がある場合）
    local tty_nr
    tty_nr=$(awk '{print $7}' /proc/self/stat 2>/dev/null)
    if [ "${tty_nr:-0}" -ne 0 ] 2>/dev/null; then
        echo "/dev/tty"
        return 0
    fi
    # 制御端末がない場合、親プロセスチェーンから pty を探す
    local pid=$$
    while [ "$pid" -gt 1 ]; do
        pid=$(awk '{print $4}' /proc/$pid/stat 2>/dev/null) || break
        local fd
        for fd in /proc/$pid/fd/0 /proc/$pid/fd/1 /proc/$pid/fd/2; do
            local target
            target=$(readlink "$fd" 2>/dev/null) || continue
            if [[ "$target" == /dev/pts/* ]]; then
                echo "$target"
                return 0
            fi
        done
    done
    return 1
}

seg_wezterm_uservar() {
    local tty_dev
    tty_dev=$(find_tty_device)
    if [ -n "$tty_dev" ] && [ -c "$tty_dev" ]; then
        printf '\033]1337;SetUserVar=%s=%s\007' 'WEZTERM_AI_HELPER' "$(printf '%s' 'claude-code' | base64)" > "$tty_dev"
    fi
}
