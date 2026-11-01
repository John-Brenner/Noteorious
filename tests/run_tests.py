"""Runs the Noteorious test suite under several Lua runtimes using `lupa`.

    pip install lupa
    python tests/run_tests.py
    python tests/run_tests.py --windower-libs /path/to/Windower/Lua/addons/libs

Windower 4 embeds LuaJIT (Lua 5.1 semantics). lupa bundles LuaJIT 2.1,
LuaJIT 2.0 and PUC Lua 5.1, so the addon is checked on all three.
"""

import argparse
import importlib
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_RUNTIMES = ["luajit21", "luajit20", "lua51"]


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--windower-libs", help="folder containing Windower's texts.lua")
    parser.add_argument("--runtime", action="append", help="lupa runtime module, e.g. luajit21 (repeatable)")
    args = parser.parse_args()

    failed = 0
    ran = 0
    for name in args.runtime or DEFAULT_RUNTIMES:
        try:
            module = importlib.import_module("lupa." + name)
        except ImportError:
            print(f"{name}: not available in this lupa build, skipped")
            continue
        lua = module.LuaRuntime()
        g = lua.globals()
        g.NOTEORIOUS_ROOT = ROOT.as_posix() + "/"
        g.NOTEORIOUS_EMBEDDED = True
        if args.windower_libs:
            g.WINDOWER_LIBS = Path(args.windower_libs).resolve().as_posix() + "/"
        sys.stdout.flush()
        result = lua.execute('return dofile(NOTEORIOUS_ROOT .. "tests/run.lua")')
        sys.stdout.flush()
        failed += int(result or 0)
        ran += 1

    if ran == 0:
        print("no Lua runtime available; install lupa (pip install lupa)")
        sys.exit(2)
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
