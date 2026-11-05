"""Build dist/factory-radar_<version>.zip from src/factory-radar.
Output: dist/for-2.0/ and dist/for-2.1/ (friends kit: dist/for-friends/).
Usage: python tools/build.py            build for Factorio 2.0 (version and factorio_version from info.json, 1.0.x)
       python tools/build.py --game 2.1 build for Factorio 2.1 (the same code, version 1.1.x, factorio_version "2.1")
The minor number of the mod version is the game version: 1.0.x = Factorio 2.0, 1.1.x = Factorio 2.1.
The changelog of a build has only the entries of its own line."""
import json, pathlib, re, sys, zipfile

root = pathlib.Path(__file__).resolve().parent.parent
src = root / "src" / "factory-radar"
info = json.loads((src / "info.json").read_text(encoding="utf-8"))
game = sys.argv[sys.argv.index("--game") + 1] if "--game" in sys.argv else info["factorio_version"]

base_major = info["version"].split(".")[0]
base_patch = int(info["version"].split(".")[2])
minor = {"2.0": 0, "2.1": 1}[game]
ver = f"{base_major}.{minor}.{base_patch if game == info['factorio_version'] else 0}"
if game != info["factorio_version"]:
    # the 2.1 line has its own patch number, taken from the newest 1.1.x entry of the changelog
    m = re.search(r"^Version: %s\.%d\.(\d+)$" % (base_major, minor), (src / "changelog.txt").read_text(encoding="utf-8"), re.M)
    ver = f"{base_major}.{minor}.{m.group(1) if m else 0}"


def changelog_for(text, minor):
    blocks = re.split(r"(?m)^-{99}\n", text)
    keep = [b for b in blocks if b.strip() and re.search(r"(?m)^Version: \d+\.%d\.\d+$" % minor, b)]
    return "".join("-" * 99 + "\n" + b for b in keep)


name = f"factory-radar_{ver}"
out = root / "dist" / f"for-{game}" / f"{name}.zip"
out.parent.mkdir(parents=True, exist_ok=True)
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
    for f in sorted(src.rglob("*")):
        if not f.is_file():
            continue
        arc = f"{name}/{f.relative_to(src).as_posix()}"
        if f.name == "info.json" and f.parent == src:
            out_info = dict(info, version=ver, factorio_version=game)
            if game == "2.1":
                # the 2.1 build needs 2.1.7 or newer (the 2.1 API was reworked up to that release)
                out_info["dependencies"] = ["base >= 2.1.7" if d.startswith("base") else d for d in info["dependencies"]]
            z.writestr(arc, json.dumps(out_info, indent=2, ensure_ascii=False))
        elif f.name == "changelog.txt" and f.parent == src:
            z.writestr(arc, changelog_for(f.read_text(encoding="utf-8"), minor))
        else:
            z.write(f, arc)
print(out)
