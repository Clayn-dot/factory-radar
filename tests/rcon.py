"""Send console commands to a running Factorio server over RCON.
Usage: python tests/rcon.py "/tr-now" "/c __factory-radar__ rcon.print(serpent.line(storage.tr.cfg))"
Needs: pip install mcrcon ; server started with --rcon-port 27015 --rcon-password x
Mod modules from a command: package.loaded["__factory-radar__/scripts/energy.lua"] (inside /c __factory-radar__ ...)."""
import sys, time, mcrcon
r = mcrcon.MCRcon("127.0.0.1", "x", 27015, timeout=600); r.connect()
for c in sys.argv[1:]:
    print(">", c[:120]); print(r.command(c)); time.sleep(0.5)
