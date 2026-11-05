"""Mock GUI test of Factory Radar without the game.
Usage:  python tests/run_tr.py ru        (or en)
        STRESS=1 python tests/run_tr.py ru   (every number formatter returns a table - catches '..' on localised strings)
        STRICT=1 python tests/run_tr.py ru   (lists every read of a global that does not exist: typos in names)
Needs:  pip install lupa
Pass:   no lines with 'GUI error' / 'attempt to' / 'traceback', and 'MISSING KEYS: 0'."""
import lupa, sys, os, pathlib
here = pathlib.Path(__file__).resolve().parent
src = (here.parent / "src" / "factory-radar").as_posix() + "/"
L = lupa.LuaRuntime(unpack_returned_tuples=True)
lang = sys.argv[1] if len(sys.argv) > 1 else "en"
L.execute('arg={"%s"}; TR_SRC=[[%s]]' % (lang, src))
strict = os.environ.get("STRICT") == "1"
if strict:
    # remember where a global that nobody defined is read (the mock defines the game's own globals itself)
    L.execute('''UNDEF = {}
setmetatable(_G, {__index = function(t, k)
  local i = debug.getinfo(2, "Sl")
  if i and not UNDEF[k] then UNDEF[k] = i.short_src .. ":" .. tostring(i.currentline) end
  return nil
end})''')
L.execute((here / "mock_tr.lua").read_text(encoding="utf-8"))
if strict:
    L.execute('local list = {} for k, v in pairs(UNDEF) do list[#list + 1] = tostring(k) .. "  " .. v end table.sort(list) '
              'print("UNDEFINED GLOBALS: " .. #list) for _, l in ipairs(list) do print("  " .. l) end')
