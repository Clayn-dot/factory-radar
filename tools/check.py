"""Static checks: ru/en locale keys match, changelog format, no mentions of other mods in player texts.
Usage: python tools/check.py"""
import pathlib, re, sys
src = pathlib.Path(__file__).resolve().parent.parent / "src" / "factory-radar"
def keys(lang):
    out, sec = set(), None
    for l in (src / "locale" / lang / "factory-radar.cfg").read_text(encoding="utf-8").splitlines():
        m = re.match(r"^\[(.+)\]$", l)
        if m: sec = m.group(1)
        elif "=" in l and sec: out.add(sec + "." + l.split("=", 1)[0])
    return out
ru, en = keys("ru"), keys("en")
bad = 0
for k in sorted(ru - en): print("only in ru:", k); bad += 1
for k in sorted(en - ru): print("only in en:", k); bad += 1
for i, l in enumerate((src / "changelog.txt").read_text(encoding="utf-8").split("\n"), 1):
    if l == "" or l == "-" * 99 or re.match(r"^Version: \d+\.\d+\.\d+$", l) or re.match(r"^Date: .+$", l) \
       or re.match(r"^  [A-Z][A-Za-z ]+:$", l) or re.match(r"^    - .+", l) or re.match(r"^      .+", l):
        continue
    print("changelog line", i, "bad:", l[:60]); bad += 1
for lang in ("ru", "en"):
    t = (src / "locale" / lang / "factory-radar.cfg").read_text(encoding="utf-8")
    for w in ["UPS Guard", "Castra", "Кастр", "Muluna", "Мулун", "Krastorio", "K2 "]:
        if w in t: print(f"{lang}: mentions '{w}'"); bad += 1
print("OK" if bad == 0 else f"{bad} problem(s)")
sys.exit(1 if bad else 0)
