"""Point SOUL.md's `icon:` at an animated sidecar.

Usage: python3 seed_soul_icon.py <SOUL.md> <sidecar-name>

The file is created with a minimal frontmatter when missing. An existing
`icon:` line is rewritten in place; otherwise one is inserted after the
opening `---`. Body and every other field are left byte-identical.
"""
import sys

path, sidecar = sys.argv[1], sys.argv[2]
line = 'icon: "%s"' % sidecar

try:
    with open(path, encoding="utf-8") as fh:
        text = fh.read()
except FileNotFoundError:
    text = ""

if not text.startswith("---"):
    text = '---\nname: "Minis"\nstyle: ""\nlang: "auto"\n---\n\n' + text

lines = text.split("\n")
end = next((i for i in range(1, len(lines)) if lines[i].strip() == "---"), None)
if end is None:
    lines = ['---', 'name: "Minis"', line, 'style: ""', 'lang: "auto"', '---', ''] + lines
else:
    hit = next((i for i in range(1, end) if lines[i].startswith("icon:")), None)
    if hit is None:
        lines.insert(end, line)
    else:
        lines[hit] = line

with open(path, "w", encoding="utf-8", newline="\n") as fh:
    fh.write("\n".join(lines))
print("seeded", path, "->", sidecar)
