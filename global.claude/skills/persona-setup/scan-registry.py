#!/usr/bin/env python3
# 目的: registry の既存 persona_config.md を走査し、分布サマリと頻出クラスタを出力
#       --projects でプロジェクト-人格対応表を出力（project_title.txt ベース）
# 関連: persona-setup SKILL.md Step 3a
# 前提: ~/Notes/claude-registry/<hostname>/<dir-name>/persona_config.md

import glob
import re
import sys
from collections import Counter
from pathlib import Path

REGISTRY = Path.home() / "Notes" / "claude-registry"


def normalize_tone(t: str) -> str:
    """口調の値から説明部分（全角括弧以降）を削除して軸名だけ取り出す"""
    for bracket in ("（", "("):
        if bracket in t:
            t = t.split(bracket)[0]
    return t.strip()


def normalize_personality(p: str) -> str:
    """性格の値から説明部分（全角括弧以降、または読点以降）を削除"""
    for bracket in ("（", "("):
        if bracket in p:
            p = p.split(bracket)[0]
    for sep in ("、", ","):
        if sep in p:
            p = p.split(sep)[0]
    return p.strip()


def strip_parens(s: str) -> str:
    """全角/半角括弧で囲まれた説明部分を再帰的に削除（ネスト対応）"""
    prev = None
    while s != prev:
        prev = s
        s = re.sub(r"（[^（）]*）", "", s)
        s = re.sub(r"\([^()]*\)", "", s)
    return s


def split_flavors(f: str) -> list[str]:
    """複数フレーバーの値を分割。各フレーバーの説明（括弧内）は事前に削除"""
    f = strip_parens(f)
    parts = re.split(r"[＋\+、,]", f)
    return [p.strip() for p in parts if p.strip()]


def parse_file(path: str) -> dict:
    """1ファイルから各フィールドを抽出。モデル別重複はファイル内で dedupe"""
    try:
        text = Path(path).read_text(encoding="utf-8")
    except Exception:
        return {"tones": [], "genders": [], "flavors": [], "names": []}

    tones_raw = re.findall(r"- \*\*口調\*\*:\s*(.+?)$", text, re.MULTILINE)
    personalities_raw = re.findall(r"- \*\*性格(?:/特徴)?\*\*:\s*(.+?)$", text, re.MULTILINE)
    genders = re.findall(r"- \*\*性別\*\*:\s*(.+?)$", text, re.MULTILINE)
    flavors_raw = re.findall(r"- \*\*フレーバー\*\*:\s*(.+?)$", text, re.MULTILINE)

    # Claude 呼び名: 呼び名行から Claude 名を抽出
    names = []
    for line in text.splitlines():
        if "呼び名" not in line:
            continue
        # 標準形式: "Claudeのこと" マーカーより後の 「...」 を Claude 名とする
        m = re.search(r"Claude\s*のこと[はを]?", line)
        if m:
            sub = line[m.end():]
            names.extend(re.findall(r"「(.+?)」", sub))
        else:
            # フォールバック (manager 等、"Claudeのこと" を使わない形式):
            # 2文目以降の「...」を Claude 名として拾う
            parts = line.split("。")
            for part in parts[1:]:
                names.extend(re.findall(r"「(.+?)」", part))

    # File 内 dedupe (モデル別に同一エントリが重複するケース対策)
    def dedupe(seq):
        seen = set()
        out = []
        for x in seq:
            key = x.strip()
            if key and key not in seen:
                seen.add(key)
                out.append(x)
        return out

    return {
        "tones": dedupe(tones_raw),
        "personalities": dedupe(personalities_raw),
        "genders": dedupe(genders),
        "flavors": [f for f in dedupe(flavors_raw) if f.strip() not in ("なし", "無し", "-")],
        "names": dedupe(names),
    }


def print_projects() -> int:
    """registry 全ホストを走査し、プロジェクト-人格対応表を markdown で出力"""
    print("# プロジェクト-人格対応表（registry から生成）")

    if not REGISTRY.is_dir():
        print()
        print("（registry 未作成。）")
        return 0

    for host_dir in sorted(REGISTRY.iterdir()):
        if not host_dir.is_dir() or host_dir.name in ("dist", "drafts"):
            continue

        rows = []
        for proj in sorted(host_dir.iterdir()):
            if not proj.is_dir():
                continue
            title_file = proj / "project_title.txt"
            config_file = proj / "persona_config.md"
            if not title_file.is_file() and not config_file.is_file():
                continue

            name = proj.name
            persona = ""
            path = ""
            summary = ""

            if title_file.is_file():
                # 1行目: "プロジェクト名 / 人格名 : 概要"、2行目: プロジェクトパス
                try:
                    lines = title_file.read_text(encoding="utf-8").splitlines()
                except Exception:
                    lines = []
                if lines:
                    head, _, summary = lines[0].strip().partition(" : ")
                    pname, _, persona = head.partition(" / ")
                    if pname.strip():
                        name = pname.strip()
                    persona = persona.strip()
                    summary = summary.strip()
                if len(lines) > 1:
                    path = lines[1].strip()
                elif summary:
                    # 旧 hook の出力形式対策: title 側の改行欠落で概要とパスが連結されたケース
                    m = re.search(r"(/(?:home|Users|root)/\S+)$", summary)
                    if m:
                        path = m.group(1)
                        summary = summary[: m.start()].strip()

            if not persona and config_file.is_file():
                persona = "、".join(parse_file(str(config_file))["names"])

            rows.append((name, persona or "（未設定）", path, summary))

        if rows:
            print()
            print(f"## {host_dir.name}")
            print()
            print("| プロジェクト | 人格 | パス | 概要 |")
            print("|---|---|---|---|")
            for name, persona, path, summary in rows:
                print(f"| {name} | {persona} | {path} | {summary} |")

    return 0


def main() -> int:
    if "--projects" in sys.argv[1:]:
        return print_projects()

    print("# 既存人格分布")
    print()

    if not REGISTRY.is_dir():
        print("（registry 未作成。初めてのPCのようです。）")
        return 0

    files = sorted(glob.glob(str(REGISTRY / "*" / "*" / "persona_config.md")))
    if not files:
        print("（registry に persona_config.md がありません。）")
        return 0

    records = [parse_file(fp) for fp in files]

    tone_counter = Counter()
    personality_counter = Counter()
    gender_counter = Counter()
    flavor_counter = Counter()
    all_names: list[str] = []
    total_personas = 0

    for rec in records:
        for t in rec["tones"]:
            tone_counter[normalize_tone(t)] += 1
            total_personas += 1
        for p in rec["personalities"]:
            personality_counter[normalize_personality(p)] += 1
        for g in rec["genders"]:
            gender_counter[g.strip()] += 1
        for f in rec["flavors"]:
            for item in split_flavors(f):
                flavor_counter[item] += 1
        all_names.extend(rec["names"])

    print(f"総数: {total_personas} 件（{len(files)} プロジェクト）")
    print()

    print("## 口調分布")
    for tone, n in tone_counter.most_common():
        print(f"  {n:>2} {tone}")
    print()

    print("## 性格分布")
    for p, n in personality_counter.most_common():
        print(f"  {n:>2} {p}")
    print()

    if gender_counter:
        print("## 性別分布")
        for g, n in gender_counter.most_common():
            print(f"  {n:>2} {g}")
        print()

    if flavor_counter:
        print("## フレーバー分布")
        for f, n in flavor_counter.most_common():
            print(f"  {n:>2} {f}")
        print()

    # Frequent cluster detection (3+ occurrences)
    tone_clusters = [(t, n) for t, n in tone_counter.items() if n >= 3]
    pers_clusters = [(p, n) for p, n in personality_counter.items() if n >= 3]
    if tone_clusters or pers_clusters:
        print("## 頻出クラスタ（3件以上）")
        for t, n in sorted(tone_clusters, key=lambda x: -x[1]):
            print(f"- 口調「{t}」: {n}件")
        for p, n in sorted(pers_clusters, key=lambda x: -x[1]):
            print(f"- 性格「{p}」: {n}件")
        print()
    else:
        print("## 頻出クラスタ")
        print("（3件以上のクラスタなし。別方向提案を中心に。）")
        print()

    # Dedupe Claude names globally
    unique_names = []
    seen = set()
    for n in all_names:
        if n not in seen:
            seen.add(n)
            unique_names.append(n)

    print("## 既存の Claude 呼び名（重複回避用）")
    if unique_names:
        print(", ".join(unique_names))
    else:
        print("（呼び名の抽出に失敗。手動確認推奨。）")

    return 0


if __name__ == "__main__":
    sys.exit(main())
