#!/usr/bin/env python3
# 目的: claude-registry の健全性検査（_log.json 欠損 / digest 無し meta の増加 / 壊れたファイル / バックアップ停滞 / journals リンク）
# 関連: ~/.claude/hooks/session_end.sh, ccexport, ~/.claude/scripts/check_journal_links.sh
# 前提: registry（既定 ~/Notes/claude-registry）がファイル同期で全ホスト分揃っていること。
#       走査だけなら sandbox 内で動くが、状態ファイルの保存と --fix は registry へ書くため
#       sandbox 外での実行が必要（excludedCommands に登録済み）。
#       journals のリンク検査は同じディレクトリの check_journal_links.sh を呼ぶ。
#
# 使い方:
#   check_registry_health.py                   # 前回チェック以降の差分（状態が無ければ全期間）
#   check_registry_health.py --since 2026-09-01
#   check_registry_health.py --since all -v    # 全期間・省略なしで列挙
#   check_registry_health.py --fix             # 自ホスト分の欠損 _log.json を ccexport で再生成
#                                              # 会話ログが残っていなければ復旧不能マーカーを置き、
#                                              # 以後は一覧から外れる（--retry-unrecoverable で戻す）
#   check_registry_health.py --json            # 機械可読出力（状態は更新しない）

import argparse
import datetime as dt
import json
import os
import shutil
import socket
import subprocess
import sys
from pathlib import Path

REGISTRY_DEFAULT = Path.home() / "Notes" / "claude-registry"
NON_HOST_DIRS = {"dist", "dist-extras", "drafts"}
STATE_BASENAME = "registry_health.json"

# 復旧不能マーカー。--fix を試みて会話ログが既に無いと分かったセッションの隣に置く。
# 状態ファイルはホストごとで他ホストからは読まれないが、マーカーはセッションと同じ場所に
# 置かれるので、どのホストから走査しても同じ判断になる（--fix は所有ホストでしかできない）。
UNRECOVERABLE_SUFFIX = "_log.unrecoverable"

# meta のクラス。legacy は旧形式の残骸（LEGACY_ERA_END 以前）で、既定では件数のみ報告する
CLS_DIGEST = "digest"          # work-logger の digest あり（session_end.sh 由来）
CLS_NODIGEST = "nodigest"      # ccexport バッチ由来。work-logger を回さずに閉じたセッション
CLS_META_ONLY = "meta_only"    # start/end だけの旧レコード
CLS_AGENT = "agent"            # サブエージェントのセッション（会話ログ自体が無い）
CLS_DEGENERATE = "degenerate"  # session_id と project しか無い退化レコード
LEGACY_CLASSES = {CLS_META_ONLY, CLS_AGENT, CLS_DEGENERATE}

# 既定値はいずれもキットの履歴上の日付。registry の生い立ちが異なる環境では
# --legacy-era-end / --backup-feature-start で上書きする。
#
# LEGACY_ERA_END: 旧形式の meta が書かれなくなった日。これより新しい legacy レコードは
#   新種の書き込み失敗を示す
LEGACY_ERA_END = "2026-04-16"
# BACKUP_FEATURE_START: reports/ バックアップ機構（backup_project_state.sh）の導入日。
#   これ以前が最終セッションのプロジェクトは、機構の無い時代に終わっているので停滞判定から除く
BACKUP_FEATURE_START = "2026-04-14"

CLS_LABEL = {
    CLS_DIGEST: "digest あり",
    CLS_NODIGEST: "digest 無し(ccexport)",
    CLS_META_ONLY: "start/end のみ(旧)",
    CLS_AGENT: "agent-*(サブエージェント)",
    CLS_DEGENERATE: "退化レコード",
}


def local_tz():
    return dt.datetime.now().astimezone().tzinfo


def parse_ts(value):
    """ISO8601（末尾 Z 可）を aware datetime にする。タイムゾーン無しはローカル扱い。空なら None"""
    if not value:
        return None
    try:
        when = dt.datetime.fromisoformat(str(value).replace("Z", "+00:00"))
    except ValueError:
        return None
    return when if when.tzinfo else when.replace(tzinfo=local_tz())


def fmt_day(when):
    return when.astimezone(local_tz()).strftime("%Y-%m-%d") if when else "-"


def classify(session_id, meta):
    if session_id.startswith("agent-"):
        return CLS_AGENT
    if str(meta.get("digest", "")).strip():
        return CLS_DIGEST
    if meta.get("first_message"):
        return CLS_NODIGEST
    if meta.get("start") or meta.get("end"):
        return CLS_META_ONLY
    return CLS_DEGENERATE


class Record:
    __slots__ = ("host", "project", "session_id", "cls", "when", "when_estimated",
                 "has_log", "session_type", "path", "unrecoverable")

    def __init__(self, host, project, session_id, cls, when, has_log, session_type,
                 path, unrecoverable=False, when_estimated=False):
        self.host = host
        self.project = project
        self.session_id = session_id
        self.cls = cls
        self.when = when
        # when が meta の時刻ではなくファイル mtime から推定されたものかどうか。
        # 一括登録・同期でまとめて付いた mtime を「最新セッション」と読み違えないために使う
        self.when_estimated = when_estimated
        self.has_log = has_log
        self.session_type = session_type
        self.path = path
        self.unrecoverable = unrecoverable

    @property
    def key(self):
        return f"{self.host}/{self.project}/{self.session_id}"

    @property
    def legacy(self):
        return self.cls in LEGACY_CLASSES


def scan(registry):
    """registry 全体を走査して records と各種の壊れもの一覧を返す"""
    records = []
    broken = []        # (種別, host, project, ファイル名)
    logs_without_meta = []
    projects = []      # (host, project, sessions_dir)
    stale_markers = []  # log が復活したのに残っている復旧不能マーカー

    if not registry.is_dir():
        sys.exit(f"registry が見つからない: {registry}")

    for host_dir in sorted(p for p in registry.iterdir() if p.is_dir()):
        host = host_dir.name
        if host in NON_HOST_DIRS or host.startswith("."):
            continue
        for proj_dir in sorted(p for p in host_dir.iterdir() if p.is_dir()):
            sessions = proj_dir / "sessions"
            if not sessions.is_dir():
                continue
            projects.append((host, proj_dir.name, sessions))

            metas, logs, marked = {}, {}, {}
            for entry in sessions.iterdir():
                name = entry.name
                if name.endswith(UNRECOVERABLE_SUFFIX):
                    marked[name[: -len(UNRECOVERABLE_SUFFIX)]] = entry
                elif ".tmp." in name or name.endswith(".tmp"):
                    broken.append(("tmp 残骸", host, proj_dir.name, name))
                elif name.endswith("_meta.json"):
                    metas[name[: -len("_meta.json")]] = entry
                elif name.endswith("_log.json"):
                    logs[name[: -len("_log.json")]] = entry

            # log が手に入った（別経路で復元された）セッションのマーカーは用済み
            for sid in sorted(set(marked) & set(logs)):
                stale_markers.append(marked.pop(sid))

            for sid, path in sorted(logs.items()):
                if path.stat().st_size == 0:
                    broken.append(("0 バイト log", host, proj_dir.name, path.name))
                if sid not in metas:
                    logs_without_meta.append(f"{host}/{proj_dir.name}/{sid}")

            for sid, path in sorted(metas.items()):
                if path.stat().st_size == 0:
                    broken.append(("0 バイト meta", host, proj_dir.name, path.name))
                    continue
                try:
                    meta = json.loads(path.read_text(encoding="utf-8"))
                except (ValueError, OSError) as exc:
                    broken.append((f"meta パース不能 ({exc.__class__.__name__})",
                                   host, proj_dir.name, path.name))
                    continue
                when = parse_ts(meta.get("end")) or parse_ts(meta.get("start"))
                when_estimated = when is None
                if when is None:
                    when = dt.datetime.fromtimestamp(path.stat().st_mtime, tz=local_tz())
                records.append(Record(
                    host=host,
                    project=proj_dir.name,
                    session_id=sid,
                    cls=classify(sid, meta),
                    when=when,
                    has_log=sid in logs,
                    session_type=meta.get("session_type") or "",
                    path=path,
                    unrecoverable=sid in marked,
                    when_estimated=when_estimated,
                ))

    return records, broken, logs_without_meta, projects, stale_markers


def backup_status(sessions_dir):
    """states/.backup_manifest の先頭行から最終バックアップ時刻を読む"""
    manifest = sessions_dir.parent / "states" / ".backup_manifest"
    if not manifest.is_file():
        return None
    try:
        head = manifest.open(encoding="utf-8").readline()
    except OSError:
        return None
    # 形式: "# backup: 2026-09-11T11:37:17 session:30ffd8e0"
    for token in head.split():
        when = parse_ts(token)
        if when:
            return when
    return None


def resolve_project_path(proj_dir):
    """registry のプロジェクトディレクトリから実プロジェクトのパスを得る（自ホストでのみ有効）

    project_title.txt の2行目がパス。無い場合はディレクトリ名から逆引きする。
    どちらでも決まらなければ None（呼び出し側は「判定できない」として扱うこと）。
    """
    title = proj_dir / "project_title.txt"
    if title.is_file():
        try:
            lines = title.read_text(encoding="utf-8", errors="replace").splitlines()
        except OSError:
            lines = []
        for line in reversed(lines):
            # 旧形式（タイトルとパスが1行に連結）でも末尾のパスを拾えるようにする
            idx = line.find("/")
            if idx < 0:
                continue
            candidate = Path(line[idx:].strip())
            if candidate.is_dir():
                return candidate
    return unflatten_dirname(Path.home(), proj_dir.name)


def unflatten_dirname(base, encoded):
    """'work-lab-newton' のような潰れた名前を、実在するディレクトリを辿って復元する

    session_start.sh の変換（$HOME を外し / と . を - に潰す）は非可逆なので、
    base から下に実在する名前と突き合わせて戻す。
    """
    if not encoded:
        return base
    try:
        entries = sorted(p for p in base.iterdir() if p.is_dir())
    except OSError:
        return None
    for entry in entries:
        token = entry.name.replace(".", "-")
        if encoded == token:
            return entry
        if encoded.startswith(token + "-"):
            found = unflatten_dirname(entry, encoded[len(token) + 1:])
            if found is not None:
                return found
    return None


def backup_exempt(project_path):
    """backup_project_state.sh が意図的にバックアップしない条件と同じ判定

    reports/ が symlink なら実体は別プロジェクトにあり、無ければそもそもキットの
    プロジェクトではない。どちらも states/ が作られないのが正しい姿。
    """
    reports = project_path / "reports"
    return reports.is_symlink() or not reports.is_dir()


def load_state(path):
    if not path.is_file():
        return None
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (ValueError, OSError):
        return None


def save_state(path, state):
    tmp = path.with_suffix(path.suffix + f".tmp.{os.getpid()}")
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        tmp.write_text(json.dumps(state, ensure_ascii=False, indent=2) + "\n",
                       encoding="utf-8")
        tmp.replace(path)
        return None
    except OSError as exc:
        try:
            tmp.unlink()
        except OSError:
            pass
        return str(exc)


def resolve_since(arg, state):
    """戻り値: (datetime or None, 説明文)"""
    if arg == "all":
        return None, "全期間"
    if arg in (None, "last"):
        previous = (state or {}).get("last_check")
        when = parse_ts(previous)
        if when:
            return when, f"前回チェック（{when.astimezone(local_tz()):%Y-%m-%d %H:%M}）以降"
        return None, "全期間（前回チェックの記録なし）"
    when = parse_ts(arg)
    if when is None:
        try:
            day = dt.datetime.strptime(arg, "%Y-%m-%d")
        except ValueError:
            sys.exit(f"--since の形式が不正: {arg}（YYYY-MM-DD / ISO8601 / last / all）")
        when = day.replace(tzinfo=local_tz())
    return when, f"{when.astimezone(local_tz()):%Y-%m-%d %H:%M} 以降"


def write_unrecoverable_marker(rec, reason):
    """復旧不能マーカーを session の隣に置く。戻り値は結果の短い説明"""
    marker = rec.path.parent / f"{rec.session_id}{UNRECOVERABLE_SUFFIX}"
    body = {
        "session_id": rec.session_id,
        "marked_at": dt.datetime.now(tz=local_tz()).isoformat(timespec="seconds"),
        "marked_by": socket.gethostname(),
        "reason": reason,
    }
    try:
        marker.write_text(json.dumps(body, ensure_ascii=False, indent=2) + "\n",
                          encoding="utf-8")
        return "マーク"
    except OSError as exc:
        return f"マーク失敗: {exc}"


def repair_missing_logs(targets, dry_run):
    """自ホスト分の欠損 _log.json を ccexport で再生成する"""
    results = []
    titles = Path.home() / ".claude" / "osc-logs"
    for rec in targets:
        out = rec.path.parent / f"{rec.session_id}_log.json"
        cmd = ["ccexport", "export", "-s", rec.session_id, "-o", str(out), "-f", "json"]
        if titles.is_dir():
            cmd += ["--titles-dir", str(titles) + "/"]
        if dry_run:
            results.append((rec, "dry-run", " ".join(cmd)))
            continue
        tmp = out.with_suffix(out.suffix + f".tmp.{os.getpid()}")
        cmd[cmd.index("-o") + 1] = str(tmp)
        try:
            proc = subprocess.run(cmd, capture_output=True, text=True, timeout=180)
        except (OSError, subprocess.SubprocessError) as exc:
            results.append((rec, "失敗", str(exc)))
            continue
        if proc.returncode == 0 and tmp.is_file() and tmp.stat().st_size > 0:
            try:
                tmp.replace(out)
                results.append((rec, "復旧", str(out)))
                continue
            except OSError as exc:
                results.append((rec, "失敗", f"mv: {exc}"))
        else:
            detail = (proc.stderr or proc.stdout or "").strip().splitlines()
            reason = detail[-1] if detail else f"exit {proc.returncode}"
            # ccexport が走った上で駄目だったなら会話ログはもう無い。
            # 次回以降の一覧から外すためマーカーを残す
            results.append((rec, "復旧不能",
                            f"{reason} [{write_unrecoverable_marker(rec, reason)}]"))
        if tmp.exists():
            try:
                tmp.unlink()
            except OSError:
                pass
    return results


def listing(items, limit, render):
    """先頭 limit 件だけ描画し、残りは件数で畳む"""
    lines = [f"    {render(x)}" for x in items[:limit]]
    if len(items) > limit:
        lines.append(f"    ... 他 {len(items) - limit} 件（-v で全件）")
    return lines


def main():
    ap = argparse.ArgumentParser(
        description="claude-registry の健全性を検査する",
        formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--registry", type=Path, default=REGISTRY_DEFAULT,
                    help=f"registry のパス（既定: {REGISTRY_DEFAULT}）")
    ap.add_argument("--since", default=None,
                    help="期間の起点。YYYY-MM-DD / ISO8601 / last（既定） / all")
    ap.add_argument("--host", default=socket.gethostname(),
                    help="自ホスト名（修復対象と状態ファイルの置き場を決める）")
    ap.add_argument("--stale-days", type=int, default=14,
                    help="この日数を超えて更新の無いホストを同期停止として報告（既定: 14）")
    ap.add_argument("--backup-lag-days", type=int, default=2,
                    help="最新セッションよりバックアップがこの日数以上古ければ報告（既定: 2）")
    ap.add_argument("--legacy-era-end", default=LEGACY_ERA_END,
                    help=f"旧形式の meta が書かれなくなった日。これより新しい legacy レコードを"
                         f"新種の失敗として報告する（既定: {LEGACY_ERA_END}）")
    ap.add_argument("--backup-feature-start", default=BACKUP_FEATURE_START,
                    help=f"バックアップ機構の導入日。これ以前に終わったプロジェクトは"
                         f"停滞判定から除く（既定: {BACKUP_FEATURE_START}）")
    ap.add_argument("--retry-unrecoverable", action="store_true",
                    help="復旧不能マーカーの付いたセッションも一覧・--fix の対象に戻す")
    ap.add_argument("--fix", action="store_true",
                    help="自ホスト分の欠損 _log.json を ccexport で再生成する（sandbox 外で実行）。"
                         "会話ログが残っていなければ復旧不能マーカーを置く")
    ap.add_argument("--dry-run", action="store_true", help="--fix の実行内容だけ表示する")
    ap.add_argument("--no-state", action="store_true", help="状態ファイルを読み書きしない")
    ap.add_argument("--no-journals", action="store_true", help="journals リンク検査を行わない")
    ap.add_argument("--json", action="store_true",
                    help="機械可読出力（状態ファイルは更新しない）")
    ap.add_argument("-v", "--verbose", action="store_true", help="省略せずに全件列挙する")
    args = ap.parse_args()

    limit = 10**9 if args.verbose else 10
    legacy_era_end = parse_ts(args.legacy_era_end)
    backup_feature_start = parse_ts(args.backup_feature_start)
    if legacy_era_end is None or backup_feature_start is None:
        sys.exit("--legacy-era-end / --backup-feature-start の形式が不正（YYYY-MM-DD）")
    state_path = args.registry / args.host / STATE_BASENAME
    state = None if args.no_state else load_state(state_path)
    since, since_label = resolve_since(args.since, state)

    records, broken, logs_without_meta, projects, stale_markers = scan(args.registry)
    now = dt.datetime.now(tz=local_tz())
    in_period = [r for r in records if since is None or r.when >= since]

    # log が復活したセッションのマーカーは意味を失っているので片付ける
    removed_markers = 0
    for marker in stale_markers:
        try:
            marker.unlink()
            removed_markers += 1
        except OSError:
            pass

    # --- 1. _log.json 欠損 ---
    gone = [r for r in records if not r.has_log and not r.legacy]
    legacy_missing = [r for r in records if not r.has_log and r.legacy]
    # --fix を試みて会話ログが残っていなかったものは一覧から外し、件数だけ出す
    unrecoverable = [] if args.retry_unrecoverable else [r for r in gone if r.unrecoverable]
    missing = [r for r in gone if r not in unrecoverable]
    # 前回の記録が無ければ今回が基準線。全件を「新規」と呼ばない
    baseline = state is None or "missing_log_ids" not in state
    known = set() if baseline else set(state["missing_log_ids"])
    new_missing = [] if baseline else [r for r in missing if r.key not in known]

    # --- 2. digest 無し meta（期間内・interactive のみ） ---
    period_by_project = {}
    for rec in in_period:
        if rec.legacy:
            continue
        slot = period_by_project.setdefault(f"{rec.host}/{rec.project}", {"total": 0, "nodigest": 0})
        slot["total"] += 1
        if rec.cls == CLS_NODIGEST and rec.session_type != "headless":
            slot["nodigest"] += 1
    nodigest_projects = sorted(
        ((k, v) for k, v in period_by_project.items() if v["nodigest"]),
        key=lambda kv: -kv[1]["nodigest"])
    nodigest_total = sum(v["nodigest"] for _, v in nodigest_projects)

    # --- 3. legacy クラスに新顔がいないか（新種の失敗の検出） ---
    # 期間指定とは独立に LEGACY_ERA_END 以降のものだけを拾う（--since all でも残骸を全件出さない）
    legacy_floor = max(since, legacy_era_end) if since else legacy_era_end
    fresh_legacy = [r for r in records if r.legacy and r.when >= legacy_floor]

    # --- 4. ホストの鮮度とバックアップ停滞 ---
    host_latest = {}
    for rec in records:
        cur = host_latest.get(rec.host)
        if cur is None or rec.when > cur:
            host_latest[rec.host] = rec.when
    stale_hosts = [(h, w) for h, w in sorted(host_latest.items())
                   if (now - w).days > args.stale_days]

    latest_by_project = {}
    for rec in records:
        # mtime 由来の時刻は registry への一括登録・同期の時刻でありセッションではない。
        # これを混ぜると、とうに終わったプロジェクトが機構の導入後まで生きて見える
        if rec.when_estimated:
            continue
        key = (rec.host, rec.project)
        cur = latest_by_project.get(key)
        if cur is None or rec.when > cur:
            latest_by_project[key] = rec.when
    backup_lag = []
    backup_exempt_count = 0
    for host, project, sessions in projects:
        latest = latest_by_project.get((host, project))
        # バックアップ機構の導入前に終わっているプロジェクトは判定しない
        if latest is None or latest < backup_feature_start:
            continue
        # 自ホストなら実プロジェクトを見て、バックアップされないのが正しいものを外す。
        # 他ホストの reports/ は覗けないので、判定できないものはそのまま報告する
        if host == args.host:
            project_path = resolve_project_path(sessions.parent)
            if project_path is not None and backup_exempt(project_path):
                backup_exempt_count += 1
                continue
        backed = backup_status(sessions)
        if backed is None:
            backup_lag.append((host, project, latest, None))
        elif (latest - backed).days >= args.backup_lag_days:
            backup_lag.append((host, project, latest, backed))

    # --- 5. ログはあるが meta が無い ---
    # --- 6. journals リンク ---
    journal_summary = None
    if not args.no_journals:
        script = Path(__file__).resolve().parent / "check_journal_links.sh"
        if script.is_file() and shutil.which("bash"):
            try:
                proc = subprocess.run(["bash", str(script)], capture_output=True,
                                      text=True, timeout=120)
                tail = [ln for ln in proc.stdout.splitlines() if ln.strip()]
                journal_summary = tail[-2:] if len(tail) >= 2 else tail
            except (OSError, subprocess.SubprocessError) as exc:
                journal_summary = [f"実行できませんでした: {exc}"]
        else:
            journal_summary = ["check_journal_links.sh が見つかりません"]

    # [2] は「work-logger を回さなかった」という運用の統計であって故障ではないので、
    # 要確認の件数には数えない（増減は前回窓との比較で見せる）
    nodigest_prev = (state or {}).get("nodigest_interactive", {})
    problems = (len(missing) + len(broken) + len(stale_hosts)
                + len(backup_lag) + len(logs_without_meta) + len(fresh_legacy))

    if args.json:
        payload = {
            "checked_at": now.isoformat(timespec="seconds"),
            "registry": str(args.registry),
            "since": since.isoformat() if since else None,
            "hosts": {h: fmt_day(w) for h, w in sorted(host_latest.items())},
            "totals": {"meta": len(records), "with_log": sum(1 for r in records if r.has_log),
                       "legacy": sum(1 for r in records if r.legacy)},
            "missing_log": [r.key for r in missing],
            "missing_log_new": [r.key for r in new_missing],
            "missing_log_legacy": len(legacy_missing),
            "missing_log_unrecoverable": [r.key for r in unrecoverable],
            "stale_markers_removed": removed_markers,
            "nodigest_interactive": {k: v for k, v in nodigest_projects},
            "fresh_legacy": [r.key for r in fresh_legacy],
            "broken": [{"kind": k, "host": h, "project": p, "file": f} for k, h, p, f in broken],
            "logs_without_meta": logs_without_meta,
            "stale_hosts": {h: fmt_day(w) for h, w in stale_hosts},
            "backup_lag": [{"host": h, "project": p, "latest_session": fmt_day(l),
                            "last_backup": fmt_day(b)} for h, p, l, b in backup_lag],
            "journal_links": journal_summary,
        }
        print(json.dumps(payload, ensure_ascii=False, indent=2))
        return 1 if problems else 0

    out = []
    out.append(f"== claude-registry 健全性チェック（{now:%Y-%m-%d %H:%M}, host={args.host}）==")
    out.append(f"registry: {args.registry}")
    out.append(f"対象期間: {since_label}  /  meta {len(records)} 件（うち期間内 {len(in_period)} 件）"
               f"・log {sum(1 for r in records if r.has_log)} 件")
    out.append("")

    out.append(f"[1] _log.json 欠損: {len(missing)} 件"
               + ("（今回が基準線）" if baseline else f"（新規 {len(new_missing)}）")
               + f"・legacy {len(legacy_missing)} 件は対象外")
    if missing:
        out += listing(missing, limit,
                       lambda r: f"{'' if baseline else ('新規 ' if r.key not in known else '継続 ')}"
                                 f"{r.key[:60]:60} {fmt_day(r.when)} {CLS_LABEL[r.cls]}")
        if any(r.host == args.host for r in missing):
            out.append("    → 自ホスト分は --fix で再エクスポートできる（sandbox 外で実行すること）")
        others = sorted({r.host for r in missing if r.host != args.host})
        if others:
            out.append(f"    → 他ホスト（{', '.join(others)}）は当該ホスト上で --fix を実行する必要がある")
    if legacy_missing:
        newest = max(r.when for r in legacy_missing)
        out.append(f"    legacy {len(legacy_missing)} 件（旧形式の残骸、最新 {fmt_day(newest)}）")
    if unrecoverable:
        hosts = ", ".join(sorted({r.host for r in unrecoverable}))
        out.append(f"    復旧不能 {len(unrecoverable)} 件（--fix 済み・会話ログが残っていない）"
                   f": {hosts}  再試行は --retry-unrecoverable")
    if removed_markers:
        out.append(f"    log が復活した {removed_markers} 件の復旧不能マーカーを削除した")
    out.append("")

    out.append(f"[2] digest 無しで終わった対話セッション: {nodigest_total} 件（期間内、参考値）")
    if nodigest_projects:
        def render_nodigest(kv):
            name, counts = kv
            prev = nodigest_prev.get(name)
            ago = f"  前回窓 {prev}" if prev is not None else ""
            return f"{name:44} {counts['nodigest']:3} / {counts['total']:3} 件{ago}"
        out += listing(nodigest_projects, limit, render_nodigest)
        out.append("    → work-logger を実行せずに閉じたセッション。headless は除外済み")
    out.append("")

    out.append(f"[3] 旧形式レコードの新顔: {len(fresh_legacy)} 件（期間内）")
    if fresh_legacy:
        out += listing(fresh_legacy, limit,
                       lambda r: f"{r.key[:60]:60} {fmt_day(r.when)} {CLS_LABEL[r.cls]}")
        out.append(f"    → {fmt_day(legacy_floor)} 以降には現れないはずの形式。新規の書き込み失敗を疑うこと")
    out.append("")

    out.append(f"[4] 壊れたファイル: {len(broken)} 件 / log はあるが meta が無い: {len(logs_without_meta)} 件")
    if broken:
        out += listing(broken, limit, lambda b: f"{b[0]}: {b[1]}/{b[2]}/{b[3]}")
    if logs_without_meta:
        out += listing(logs_without_meta, limit, lambda s: s)
    out.append("")

    out.append("[5] ホストの鮮度")
    for host, when in sorted(host_latest.items()):
        mark = "  停止?" if (now - when).days > args.stale_days else ""
        out.append(f"    {host:10} 最新セッション {fmt_day(when)}{mark}")
    missing_hosts = sorted({h for h, _, _ in projects} - set(host_latest))
    for host in missing_hosts:
        out.append(f"    {host:10} セッション記録なし")
    out.append("")

    out.append(f"[6] バックアップ停滞: {len(backup_lag)} プロジェクト")
    if backup_lag:
        out += listing(backup_lag, limit,
                       lambda t: f"{t[0] + '/' + t[1]:46} 最新セッション {fmt_day(t[2])} / "
                                 f"バックアップ {fmt_day(t[3]) if t[3] else '無し'}")
    if backup_exempt_count:
        out.append(f"    （自ホストの対象外 {backup_exempt_count} 件を除外: "
                   f"reports/ が無い、または symlink）")
    out.append("")

    if journal_summary is not None:
        out.append("[7] journals の会話ログリンク（check_journal_links.sh）")
        out += [f"    {line}" for line in journal_summary]
        out.append("")

    fix_results = []
    if args.fix:
        targets = [r for r in missing if r.host == args.host]
        out.append(f"[fix] 自ホスト分の欠損 log: {len(targets)} 件")
        fix_results = repair_missing_logs(targets, args.dry_run)
        out += listing(fix_results, limit,
                       lambda t: f"{t[1]}: {t[0].key} {t[2]}")
        out.append("")

    out.append("異常なし" if problems == 0 else f"要確認: 合計 {problems} 件")

    if not args.no_state:
        repaired = {r.key for r, status, _ in fix_results if status == "復旧"}
        new_state = {
            "host": args.host,
            "last_check": now.isoformat(timespec="seconds"),
            "totals": {"meta": len(records),
                       "with_log": sum(1 for r in records if r.has_log),
                       "legacy": sum(1 for r in records if r.legacy)},
            "missing_log_ids": sorted(r.key for r in missing if r.key not in repaired),
            "missing_log_legacy": len(legacy_missing),
            "missing_log_unrecoverable": len(unrecoverable),
            "nodigest_interactive": {k: v["nodigest"] for k, v in nodigest_projects},
            "broken": len(broken),
        }
        error = save_state(state_path, new_state)
        if error:
            out.append(f"（状態ファイルを保存できませんでした: {error}）")
            out.append("（registry への書き込みには sandbox 外での実行が必要。状態を使わない場合は --no-state を指定する）")
        else:
            out.append(f"（状態を更新しました: {state_path}）")

    print("\n".join(out))
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
