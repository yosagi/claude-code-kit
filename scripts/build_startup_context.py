#!/usr/bin/env python3
"""
グローバル KB からプロジェクトの関心タグに基づいてコンテキストを動的に組み立て、
stdout に出力する。claude-code wrapper から呼ばれ、出力は
tmp/global_kb_context.md に書き出されて CLAUDE.md の @ インクルードで読み込まれる。

使い方:
    python3 build_startup_context.py <project_dir>

設計:
- 全ホストの registry/<hostname>/kb/ を走査（registry はホスト名以下しか書き込まない contract のため、
  ホスト非依存の共通 kb/ は置かない）
- 同名ファイルは mtime が新しい方を採用（ホスト間重複排除）
- 実効 interests = プロジェクト kb_interests ∪ ホスト kb_interests
- inject: full → 全文注入
- inject: index → タイトル+パスのみ列挙（AI が必要に応じて Read 可能）
"""

import re
import socket
import sys
from pathlib import Path

REGISTRY_BASE = Path.home() / "Notes" / "claude-registry"


def parse_frontmatter(text):
    """YAML frontmatter を簡易パース（PyYAML 不要）"""
    m = re.match(r'^---\s*\n(.*?)\n---\s*\n', text, re.DOTALL)
    if not m:
        return {}, text
    fm_text = m.group(1)
    body = text[m.end():]
    fm = {}
    for line in fm_text.split('\n'):
        line = line.strip()
        if ':' not in line:
            continue
        key, val = line.split(':', 1)
        key = key.strip()
        val = val.strip()
        # [tag1, tag2] 形式のリストをパース
        if val.startswith('[') and val.endswith(']'):
            val = [v.strip() for v in val[1:-1].split(',') if v.strip()]
        fm[key] = val
    return fm, body


def read_interests(project_dir):
    """project_context.md から kb_interests を読み取る"""
    ctx_path = Path(project_dir) / "reports" / "project_context.md"
    if not ctx_path.exists():
        return []
    text = ctx_path.read_text(encoding='utf-8')
    m = re.search(r'kb_interests:\s*\[([^\]]*)\]', text)
    if not m:
        return []
    return [t.strip() for t in m.group(1).split(',') if t.strip()]


def read_host_interests():
    """registry/<hostname>/kb_interests から読み取る（1行1タグ）"""
    hostname = socket.gethostname()
    interests_path = REGISTRY_BASE / hostname / "kb_interests"
    if not interests_path.exists():
        return []
    lines = interests_path.read_text(encoding='utf-8').strip().split('\n')
    return [line.strip() for line in lines if line.strip() and not line.strip().startswith('#')]


def collect_kb_files():
    """全ホストの kb/ を走査し、同名ファイルは最新を採用"""
    kb_map = {}  # filename -> (path, mtime)
    if not REGISTRY_BASE.exists():
        return {}
    for host_dir in REGISTRY_BASE.iterdir():
        if not host_dir.is_dir() or host_dir.name in ('dist', 'drafts', 'kb'):
            continue
        kb_dir = host_dir / "kb"
        if not kb_dir.is_dir():
            continue
        for f in kb_dir.glob("*.md"):
            mtime = f.stat().st_mtime
            if f.name not in kb_map or mtime > kb_map[f.name][1]:
                kb_map[f.name] = (f, mtime)
    return {name: path for name, (path, _) in kb_map.items()}


def build_context(project_dir):
    project_interests = set(read_interests(project_dir))
    host_interests = set(read_host_interests())
    interests = project_interests | host_interests
    if not interests:
        return ""

    kb_files = collect_kb_files()
    if not kb_files:
        return ""

    # タグでフィルタリング
    full_entries = []
    index_entries = []

    for name, path in sorted(kb_files.items()):
        text = path.read_text(encoding='utf-8')
        fm, body = parse_frontmatter(text)
        tags = set(fm.get('tags', []))
        if not tags & interests:
            continue
        inject = fm.get('inject', 'index')
        summary = fm.get('summary', name)
        if inject == 'full':
            full_entries.append((name, summary, body.strip(), str(path)))
        else:
            index_entries.append((name, summary, str(path)))

    if not full_entries and not index_entries:
        return ""

    parts = []
    parts.append("[Global KB: プロジェクトの関心タグにマッチした横断知見]")
    parts.append("")

    for name, summary, body, path in full_entries:
        parts.append(f"### {summary}\n\n{body}")
        parts.append("")

    if index_entries:
        parts.append("### 参照可能な関連 KB（Read で全文取得可能）")
        for name, summary, path in index_entries:
            parts.append(f"- {summary}: `{path}`")

    return '\n'.join(parts).strip()


if __name__ == '__main__':
    if len(sys.argv) < 2:
        print("Usage: build_startup_context.py <project_dir>", file=sys.stderr)
        sys.exit(1)
    result = build_context(sys.argv[1])
    if result:
        print(result)
