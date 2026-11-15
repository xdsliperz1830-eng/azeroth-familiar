"""Run the Crates fixture tests (tests/crates_test.lua) in Lua 5.1; requires a locally installed Lua 5.1 DLL.
Usage: python tests/run.py [path/to/lua51.dll]
The runtime is a development dependency and is not shipped in the addon.
"""
import ctypes
import os
import sys
from pathlib import Path

root = Path(__file__).resolve().parents[1]
os.chdir(root)
runtime = sys.argv[1] if len(sys.argv) > 1 else r'C:\Program Files\obs-studio\bin\64bit\lua51.dll'
lua = ctypes.CDLL(runtime)
lua.luaL_newstate.restype = ctypes.c_void_p
lua.luaL_openlibs.argtypes = [ctypes.c_void_p]
lua.luaL_loadfile.argtypes = [ctypes.c_void_p, ctypes.c_char_p]
lua.luaL_loadfile.restype = ctypes.c_int
lua.lua_pcall.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_int, ctypes.c_int]
lua.lua_pcall.restype = ctypes.c_int
lua.lua_tolstring.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_void_p]
lua.lua_tolstring.restype = ctypes.c_char_p
lua.lua_settop.argtypes = [ctypes.c_void_p, ctypes.c_int]
lua.lua_close.argtypes = [ctypes.c_void_p]
state = lua.luaL_newstate()
lua.luaL_openlibs(state)
try:
    for path in sorted([p for p in root.rglob('*.lua') if 'tests' not in p.parts and '.git' not in p.parts]):
        if lua.luaL_loadfile(state, str(path).encode()):
            raise RuntimeError(lua.lua_tolstring(state, -1, None).decode())
        lua.lua_settop(state, 0)
    print('Syntax: all addon Lua modules passed', flush=True)
    if lua.luaL_loadfile(state, b'tests/crates_test.lua') or lua.lua_pcall(state, 0, 0, 0):
        raise RuntimeError(lua.lua_tolstring(state, -1, None).decode())
finally:
    lua.lua_close(state)
