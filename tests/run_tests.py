"""Runs the Noteorious tests under the Lua runtimes bundled with `lupa`.

    pip install lupa
    python tests/run_tests.py

Windower 4 embeds LuaJIT (Lua 5.1 semantics); lupa bundles LuaJIT 2.1,
LuaJIT 2.0 and PUC Lua 5.1, so the addon is checked on all three.
"""

import importlib
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RUNTIMES = ["luajit21", "luajit20", "lua51"]


def main():
    failed = ran = 0
    for name in RUNTIMES:
        try:
            module = importlib.import_module("lupa." + name)
        except ImportError:
            print(f"{name}: not in this lupa build, skipped")
            continue
        with tempfile.TemporaryDirectory() as tmp:
            (Path(tmp) / "data").mkdir()
            lua = module.LuaRuntime()
            lua.globals().NOTEORIOUS_ROOT = ROOT.as_posix() + "/"
            lua.globals().TEST_DIR = Path(tmp).as_posix() + "/"
            sys.stdout.flush()
            failed += int(lua.execute('return dofile(NOTEORIOUS_ROOT .. "tests/run.lua")') or 0)
            sys.stdout.flush()
            ran += 1
    if ran == 0:
        print("no Lua runtime available; install lupa (pip install lupa)")
        sys.exit(2)
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
