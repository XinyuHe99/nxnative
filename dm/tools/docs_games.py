#!/usr/bin/env python3
# Writes the games list in README.md (between its list markers) from docs/games.tsv: one line per row of the table, in the table's order.
# The table is the source: a new game is a row in it (usually at the end), so two pull requests that each add a game change one line each; .gitattributes merges the table
# with the union driver. Columns: name (the link text), note (a remark after the name, such as "60 fps with 1.0.1"; empty for most games) and the base game's title ID, which
# links the name to its game note.
# Run it after changing the table; --check only reports whether README.md is current (dm/tools/tests/test_docs.py runs it).
# Usage: docs_games.py [--check]
import pathlib, re, sys

REPO = pathlib.Path(__file__).resolve().parents[2]
TABLE = REPO / 'docs' / 'games.tsv'
OUT = REPO / 'README.md'
BEGIN = '<!-- games list: written by dm/tools/docs_games.py from docs/games.tsv; change the table, then run it -->'
END = '<!-- end of games list -->'


def rows():
    out = []
    seen = {'name': {}, 'title ID': {}}
    for n, line in enumerate(TABLE.read_text(encoding='utf-8').splitlines(), 1):
        if not line.strip() or line.startswith('#'): continue
        c = line.split('\t')
        if len(c) != 3: sys.exit(f'{TABLE.name}:{n}: 3 columns expected (name, note, title ID), {len(c)} found')
        name, note, tid = c
        if not re.fullmatch(r'[0-9A-F]{16}', tid): sys.exit(f'{TABLE.name}:{n}: a title ID is 16 hex digits: {tid!r}')
        if not (REPO / 'dm' / 'games' / tid / 'README.md').is_file(): sys.exit(f'{TABLE.name}:{n}: no game note dm/games/{tid}/README.md')
        # A union merge can retain two different lines for the same game, so check its title ID too.
        for field, value in (('name', name), ('title ID', tid)):
            if value in seen[field]:
                sys.exit(f'{TABLE.name}:{n}: duplicate {field} {value!r} (first at line {seen[field][value]}): merge the rows by hand')
            seen[field][value] = n
        out.append((name, note, tid))
    return out


def plain(s):
    # Names and notes are plain text: escape what Markdown would read as markup.
    return re.sub(r'([\\`*_\[\]<>])', r'\\\1', s)


def item(name, note, tid):
    detail = f' — {plain(note)}' if note else ''   # a game with no remark has only its name
    return f'- [{plain(name)}](dm/games/{tid}/README.md){detail}'


def games():
    return '\n'.join(item(*x) for x in rows())


def readme():
    text = OUT.read_text(encoding='utf-8')
    if text.count(BEGIN) != 1 or text.count(END) != 1: sys.exit(f'README.md: the games list markers ({BEGIN} … {END}) must appear once each')
    head, rest = text.split(BEGIN)
    if END not in rest: sys.exit('README.md: the games list end marker must follow the begin marker')
    return head + BEGIN + '\n' + games() + '\n' + END + rest.split(END, 1)[1]


if __name__ == '__main__':
    text = readme()
    if '--check' in sys.argv[1:]:
        if OUT.read_text(encoding='utf-8') != text: sys.exit('README.md: the games list is out of date: run dm/tools/docs_games.py')
    else:
        OUT.write_text(text, encoding='utf-8')
