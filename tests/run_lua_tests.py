"""Run Lua 5.1 source checks with a CSP API double, never the game renderer.

Requires the optional Python package lupa. It is not a game dependency.
"""
import argparse
import json
import os
from pathlib import Path

from lupa.lua51 import LuaRuntime, lua_type


def run(path):
    runtime = LuaRuntime(unpack_returned_tuples=True)

    def to_python(value):
        if lua_type(value) != "table":
            return value
        keys = list(value.keys())
        if keys and all(isinstance(k, (int, float)) and k == int(k) for k in keys):
            if sorted(keys) == list(range(1, len(keys) + 1)):
                return [to_python(value[i]) for i in range(1, len(keys) + 1)]
        return {key: to_python(value[key]) for key in keys}

    def to_lua(value):
        if isinstance(value, (list, dict)):
            pairs = enumerate(value, 1) if isinstance(value, list) else value.items()
            table = runtime.table()
            for key, item in pairs:
                table[key] = to_lua(item)
            return table
        return value

    runtime.globals().JSON = runtime.table_from({
        "stringify": lambda data: json.dumps(to_python(data), separators=(",", ":")),
        "parse": lambda text: to_lua(json.loads(text)),
    })
    print(f"Running {path}", flush=True)
    runtime.execute(Path(path).read_text())


if __name__ == "__main__":
    os.chdir(Path(__file__).resolve().parents[1])
    parser = argparse.ArgumentParser()
    parser.add_argument("files", nargs="*", default=[])
    args = parser.parse_args()
    for test in args.files or sorted(Path("tests").glob("test_*.lua")):
        run(test)
