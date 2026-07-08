#!/usr/bin/env python3
# 目的: グローバル KB（claude-registry/*/kb/*.md）の既存タグ一覧を markdown で出力する。
#       global-kb スキルが SKILL.md の !`cmd` 動的展開で呼び出し、
#       タグの新設・再利用の判断材料をスキルロード時にコンテキストへ埋め込む。
# 関連: build_startup_context.py（読み取り側の注入ロジック）、global-kb SKILL.md
# 前提: registry は ~/Notes/claude-registry。同名ファイルは mtime が新しい方を採用
#       （読み取り側の重複排除と同じ規則）。

import re
from pathlib import Path

REGISTRY = Path.home() / "Notes" / "claude-registry"


def parse_frontmatter_tags(path: Path):
    """frontmatter の tags: [a, b] を読む。なければ空リスト。"""
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except OSError:
        return []
    if not lines or lines[0].strip() != "---":
        return []
    for line in lines[1:30]:
        if line.strip() == "---":
            break
        m = re.match(r"^tags:\s*\[(.*)\]\s*$", line.strip())
        if m:
            return [t.strip() for t in m.group(1).split(",") if t.strip()]
    return []


def main():
    if not REGISTRY.is_dir():
        print("（registry が見つかりません: ~/Notes/claude-registry）")
        return

    # 同名ファイルは mtime が新しい方を採用（読み取り側と同じ規則）
    newest = {}  # filename -> (mtime, path)
    for kb_file in REGISTRY.glob("*/kb/*.md"):
        mtime = kb_file.stat().st_mtime
        cur = newest.get(kb_file.name)
        if cur is None or mtime > cur[0]:
            newest[kb_file.name] = (mtime, kb_file)

    tag_files = {}  # tag -> [filename]
    for name, (_, path) in sorted(newest.items()):
        for tag in parse_frontmatter_tags(path):
            tag_files.setdefault(tag, []).append(name)

    if not tag_files:
        print("（既存タグなし）")
    else:
        for tag in sorted(tag_files, key=lambda t: (-len(tag_files[t]), t)):
            files = ", ".join(tag_files[tag])
            print(f"- **{tag}** ({len(tag_files[tag])}件): {files}")

    # ホスト単位の kb_interests（注入先設定の参考情報）
    print()
    print("ホスト単位の kb_interests:")
    found = False
    for interests_file in sorted(REGISTRY.glob("*/kb_interests")):
        tags = [
            line.strip()
            for line in interests_file.read_text(encoding="utf-8").splitlines()
            if line.strip() and not line.strip().startswith("#")
        ]
        print(f"- {interests_file.parent.name}: {', '.join(tags) if tags else '（なし）'}")
        found = True
    if not found:
        print("- （設定なし）")


if __name__ == "__main__":
    main()
