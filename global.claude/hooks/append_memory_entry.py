#!/usr/bin/env python3
"""
記憶ドラフトの追記処理

Usage: append_memory_entry.py <draft_file> <target> <project_dir>
  target: work_history | diary

ドラフトファイルのエントリを main ファイルと archive ファイルの両方に追記する。
追記後、ドラフトファイルを削除する。
"""

import sys
from pathlib import Path

TARGETS = {
    "work_history": {
        "main": "reports/memory/work_history.md",
        "archive": "reports/memory/work_history_archive.md",
        "section_header": "## 最近の作業",
    },
    "diary": {
        "main": "reports/personas/diary.md",
        "archive": "reports/personas/diary_archive.md",
        "section_header": "## 印象的なエピソード",
    },
}


def read_draft(draft_path: Path) -> str:
    content = draft_path.read_text(encoding="utf-8").strip()
    if not content:
        return ""
    return content


def prepend_to_main(file_path: Path, entries: str, section_header: str) -> None:
    if not file_path.exists():
        print(f"Warning: Main file not found: {file_path}", file=sys.stderr)
        return

    content = file_path.read_text(encoding="utf-8")
    lines = content.split("\n")

    insert_pos = None
    for i, line in enumerate(lines):
        if line.strip() == section_header:
            insert_pos = i + 1
            # skip blank lines after header
            while insert_pos < len(lines) and lines[insert_pos].strip() == "":
                insert_pos += 1
            break

    if insert_pos is None:
        print(
            f"Warning: Section '{section_header}' not found in {file_path}",
            file=sys.stderr,
        )
        return

    entry_lines = entries.split("\n")
    new_lines = lines[:insert_pos] + [""] + entry_lines + [""] + lines[insert_pos:]
    file_path.write_text("\n".join(new_lines), encoding="utf-8")


ARCHIVE_TEMPLATES = {
    "work_history_archive.md": "# 作業履歴アーカイブ\n\nwork_history.md から溢れた作業履歴を保存。\n\n",
    "diary_archive.md": "# 日記アーカイブ\n\ndiary.md から溢れたエピソードを保存。\n\n",
}


def prepend_to_archive(file_path: Path, entries: str) -> None:
    if not file_path.exists():
        template = ARCHIVE_TEMPLATES.get(file_path.name, f"# {file_path.stem}\n\n")
        file_path.write_text(template, encoding="utf-8")
        print(f"Created archive: {file_path}", file=sys.stderr)

    content = file_path.read_text(encoding="utf-8")
    lines = content.split("\n")

    # find first content line after file header
    # header is typically: "# title\n\ndescription\n\n"
    # insert before first "## " heading or first "- 20" entry
    insert_pos = len(lines)
    for i, line in enumerate(lines):
        if line.startswith("## ") or line.startswith("- 20"):
            insert_pos = i
            break

    entry_lines = entries.split("\n")
    new_lines = lines[:insert_pos] + entry_lines + [""] + lines[insert_pos:]
    file_path.write_text("\n".join(new_lines), encoding="utf-8")


def main():
    if len(sys.argv) != 4:
        print(f"Usage: {sys.argv[0]} <draft_file> <target> <project_dir>", file=sys.stderr)
        sys.exit(1)

    draft_path = Path(sys.argv[1])
    target = sys.argv[2]
    project_dir = Path(sys.argv[3])

    if target not in TARGETS:
        print(f"Error: Unknown target '{target}'. Expected: {', '.join(TARGETS)}", file=sys.stderr)
        sys.exit(1)

    if not draft_path.exists():
        print(f"Error: Draft file not found: {draft_path}", file=sys.stderr)
        sys.exit(1)

    entries = read_draft(draft_path)
    if not entries:
        print(f"Warning: Empty draft file: {draft_path}", file=sys.stderr)
        draft_path.unlink()
        return

    config = TARGETS[target]
    main_path = project_dir / config["main"]
    archive_path = project_dir / config["archive"]

    prepend_to_main(main_path, entries, config["section_header"])
    prepend_to_archive(archive_path, entries)

    draft_path.unlink()
    print(f"Memory entry appended: {target} ({main_path.name} + {archive_path.name})")


if __name__ == "__main__":
    main()
