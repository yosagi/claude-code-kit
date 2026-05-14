#!/usr/bin/env python3
"""
note-logger のドラフトを journals の "* Claude 雑記" セクションに追記する

使い方:
    append_journal.py <draft_file>

ドラフトファイル名: YYYY-MM-DD_HHMMSS_note-logger_<project>@<hostname>.org
ドラフトファイル内容（完成形）:

    ** HH:MM [project@host] タイトル
    本文...

処理:
    1. ~/Notes/journals/YYYY-MM-DD.org を開く（なければ作成）
    2. "* Claude 雑記" セクションを探す（なければ先頭に作成）
    3. そのセクションの末尾（次の level-1 見出しの前、または EOF）にドラフト内容をそのまま追記
    4. ドラフトファイルを削除
"""

import sys
import re
from pathlib import Path

SECTION_TITLE = "Claude 雑記"


def parse_org_sections(content: str) -> list[dict]:
    lines = content.split('\n')
    result = []
    for line in lines:
        match = re.match(r'^(\*+)\s+(.*)$', line)
        if match:
            result.append({
                'line': line,
                'level': len(match.group(1)),
                'is_heading': True,
                'heading_text': match.group(2),
            })
        else:
            result.append({
                'line': line,
                'level': 0,
                'is_heading': False,
                'heading_text': None,
            })
    return result


def find_section(parsed: list[dict], level: int, text: str) -> int | None:
    for i, item in enumerate(parsed):
        if item['is_heading'] and item['level'] == level and item['heading_text'] == text:
            return i
    return None


def find_section_end(parsed: list[dict], start: int) -> int:
    start_level = parsed[start]['level']
    for i in range(start + 1, len(parsed)):
        if parsed[i]['is_heading'] and parsed[i]['level'] <= start_level:
            return i
    return len(parsed)


def parse_date_from_filename(draft_path: Path) -> str:
    name = draft_path.stem
    parts = name.split('_', 3)
    if len(parts) != 4:
        raise ValueError(f"Unexpected draft filename: {draft_path}")
    return parts[0]


def append_entry(journal_path: Path, entry: str) -> None:
    """
    journal ファイルの "* Claude 雑記" セクション末尾に entry を追記する
    entry は既に "** HH:MM ..." ヘッダを含む完成形。
    """
    if not journal_path.exists():
        journal_path.parent.mkdir(parents=True, exist_ok=True)
        content = f"#+OPTIONS: ^:{{}}\n* {SECTION_TITLE}\n{entry}\n"
        journal_path.write_text(content)
        return

    content = journal_path.read_text()
    parsed = parse_org_sections(content)

    section_idx = find_section(parsed, 1, SECTION_TITLE)

    if section_idx is None:
        # 雑記セクションがない → 新規作成
        # 配置順: 作業ログ → 雑記 を強制するため、作業ログがあればその末尾に挿入
        lines = content.split('\n')
        worklog_idx = find_section(parsed, 1, "Claude 作業ログ")
        if worklog_idx is not None:
            insert_pos = find_section_end(parsed, worklog_idx)
        else:
            # どちらも無い → ヘッダ行 (#+) の直後
            insert_pos = 0
            for i, line in enumerate(lines):
                if line.startswith('#+'):
                    insert_pos = i + 1
                else:
                    break
        new_lines = lines[:insert_pos] + [f"* {SECTION_TITLE}", entry] + lines[insert_pos:]
        journal_path.write_text('\n'.join(new_lines))
        return

    # 雑記セクションの末尾に追記
    section_end = find_section_end(parsed, section_idx)
    lines = content.split('\n')

    # 末尾の空行を詰めて、最後の非空行の後に挿入
    insert_pos = section_end
    while insert_pos > section_idx + 1 and lines[insert_pos - 1].strip() == '':
        insert_pos -= 1
    new_lines = lines[:insert_pos] + [entry] + lines[insert_pos:]

    journal_path.write_text('\n'.join(new_lines))


def main():
    if len(sys.argv) != 2:
        print("Usage: append_journal.py <draft_file>", file=sys.stderr)
        sys.exit(1)

    draft_path = Path(sys.argv[1])
    if not draft_path.exists():
        print(f"Error: Draft file not found: {draft_path}", file=sys.stderr)
        sys.exit(1)

    try:
        date = parse_date_from_filename(draft_path)
    except ValueError as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)

    entry = draft_path.read_text().rstrip('\n')
    if not entry:
        print("Error: Draft file is empty", file=sys.stderr)
        sys.exit(1)

    journal_dir = Path.home() / "Notes" / "journals"
    journal_path = journal_dir / f"{date}.org"

    append_entry(journal_path, entry)

    draft_path.unlink()

    print(f"Successfully appended to {journal_path}")


if __name__ == "__main__":
    main()
