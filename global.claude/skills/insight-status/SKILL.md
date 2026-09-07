---
name: insight-status
description: 定期 insight の状況確認（review は開始しない）。前回の定期実行で成果物が出たか、未レビューのレポートが何件か、次回はいつかを読み取り専用で報告する。ユーザーが「insight の状況」「insight は動いてる？」「insight-status」と言ったとき、および briefing スキルから使う
user_invocable: true
allowed-tools: Bash(~/.claude/skills/insight-status/insight-status.sh:*)
---

# insight-status スキル

定期 insight（systemd timer による `claude -p "/insight"`）の状況を確認する。
**読み取り専用**。レポートの review は開始しない（それは `/insight-review` の責務）。

## 手順

1. スクリプトを実行する。引数はプロジェクトルート（システムプロンプトで把握しているパスを渡す）

   ```bash
   ~/.claude/skills/insight-status/insight-status.sh /path/to/project
   ```

2. 出力（markdown 数行）をそのまま提示する。要約や言い換えはしない

3. 出力に応じて次の一手を一言添える
   - **レポートなし → 失敗の疑い**: `journalctl --user -u insight-<unit>.service` で原因を見ることを提案する
     （session limit・sandbox 拒否・ネットワークなど）。自分では journalctl を追わない
   - **完了記録なし**: 走行中なら待つ。前回発火から数時間以上経っていれば途中停止として同上
   - **未レビュー N 件**: `/insight-review` で処理できることを伝える。開始はユーザーの指示があってから
   - **Phase 0 スキップ**: 活動がなければ正常。数週続くプロジェクトは定期実行の対象から外す判断材料になる

## スクリプトが見るもの

- `~/.config/systemd/user/insight-<unit>.timer` — 定期実行の有無、`OnCalendar`、次回予定（`systemd-analyze calendar`）
- `journalctl --user -u insight-<unit>.service` — 前回の発火・完了時刻、Phase 0 スキップの文言
- `reports/insight/*_insight.md` — 最新レポート、`## Review 結果` 節のないもの（未レビュー）
- `reports/inbox/INDEX.md` — `from_insight` の未読・既読未完了
- `reports/jobs/` — ローカルジョブ件数

`systemctl --user` は使わない（D-Bus の UNIX ソケットが必要で sandbox 内では動かない）。
unit 名の変換は insight-schedule.sh と同じ（`$HOME` を除いたパスの `/` と `.` を `-` に）。

## やらないこと

- `/insight-review` の開始、レポートや inbox の変更
- timer / service の有効化・無効化・手動起動（それは `insight-schedule.sh` の責務）
