#!/usr/bin/env python3
"""
journals ファイルにエントリを追記する

使い方:
    append_journal.py <日付> <プロジェクト名> <ドラフトファイル>

例:
    append_journal.py 2026-02-05 claude /tmp/draft.md

処理:
    1. ~/Notes/journals/YYYY-MM-DD.org を開く（なければ作成）
    2. "* Claude 作業ログ" セクションを探す（なければファイル先頭に作成）
    3. "** プロジェクト名" サブセクションを探す
       - なければ作成し、ドラフトの内容を追記
       - あればそのサブセクションの末尾に追記
    4. ドラフトファイルを削除
"""

import sys
import re
from pathlib import Path


def parse_org_sections(content: str) -> list[dict]:
    """
    org ファイルを行ごとにパースし、各行の情報を返す

    Returns:
        list of dict: 各行について {line, level, is_heading, heading_text}
        - level: 見出しの場合は * の数、それ以外は 0
        - is_heading: 見出し行かどうか
        - heading_text: 見出しの場合はテキスト部分
    """
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
    """
    指定レベル・テキストの見出しを探す

    Returns:
        見つかった場合は行番号（0-indexed）、なければ None
    """
    for i, item in enumerate(parsed):
        if item['is_heading'] and item['level'] == level and item['heading_text'] == text:
            return i
    return None


def find_section_end(parsed: list[dict], start: int) -> int:
    """
    セクションの終わり（次の同レベル以上の見出し、またはファイル末尾）を探す

    Returns:
        セクション末尾の次の行番号（挿入位置）
    """
    start_level = parsed[start]['level']
    for i in range(start + 1, len(parsed)):
        if parsed[i]['is_heading'] and parsed[i]['level'] <= start_level:
            return i
    return len(parsed)


def append_entry(journal_path: Path, project: str, entry: str) -> None:
    """
    journal ファイルにエントリを追記する
    """
    # ファイルが存在しない場合は新規作成
    if not journal_path.exists():
        journal_path.parent.mkdir(parents=True, exist_ok=True)
        content = f"#+OPTIONS: ^:{{}}\n* Claude 作業ログ\n** {project}\n{entry}\n"
        journal_path.write_text(content)
        return

    # 既存ファイルを読み込み
    content = journal_path.read_text()
    parsed = parse_org_sections(content)

    # "* Claude 作業ログ" を探す
    log_section_idx = find_section(parsed, 1, "Claude 作業ログ")

    if log_section_idx is None:
        # 作業ログセクションがない → ヘッダ行(#+)の後に追加
        lines = content.split('\n')
        insert_pos = 0
        for i, line in enumerate(lines):
            if line.startswith('#+'):
                insert_pos = i + 1
            else:
                break
        new_lines = lines[:insert_pos] + [f"* Claude 作業ログ\n** {project}\n{entry}\n"] + lines[insert_pos:]
        journal_path.write_text('\n'.join(new_lines))
        return

    # "** プロジェクト名" を探す（作業ログセクション内で）
    log_section_end = find_section_end(parsed, log_section_idx)
    project_idx = None
    for i in range(log_section_idx + 1, log_section_end):
        if parsed[i]['is_heading'] and parsed[i]['level'] == 2 and parsed[i]['heading_text'] == project:
            project_idx = i
            break

    lines = content.split('\n')

    if project_idx is None:
        # プロジェクトセクションがない → 作業ログセクション直下に追加
        insert_pos = log_section_idx + 1
        new_lines = lines[:insert_pos] + [f"** {project}", entry] + lines[insert_pos:]
    else:
        # プロジェクトセクションがある → その末尾に追記
        project_end = find_section_end(parsed, project_idx)
        # 末尾の空行を考慮して、最後の非空行の後に挿入
        insert_pos = project_end
        while insert_pos > project_idx + 1 and lines[insert_pos - 1].strip() == '':
            insert_pos -= 1
        new_lines = lines[:insert_pos] + [entry] + lines[insert_pos:]

    journal_path.write_text('\n'.join(new_lines))


def main():
    if len(sys.argv) != 4:
        print("Usage: append_journal.py <date> <project> <draft_file>", file=sys.stderr)
        sys.exit(1)

    date = sys.argv[1]
    project = sys.argv[2]
    draft_path = Path(sys.argv[3])

    if not draft_path.exists():
        print(f"Error: Draft file not found: {draft_path}", file=sys.stderr)
        sys.exit(1)

    entry = draft_path.read_text().rstrip('\n')
    if not entry:
        print("Error: Draft file is empty", file=sys.stderr)
        sys.exit(1)

    journal_dir = Path.home() / "Notes" / "journals"
    journal_path = journal_dir / f"{date}.org"

    append_entry(journal_path, project, entry)

    # ドラフトファイルを削除
    draft_path.unlink()

    print(f"Successfully appended to {journal_path}")


if __name__ == "__main__":
    main()
