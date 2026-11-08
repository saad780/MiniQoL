from pathlib import Path
import sys
from lupa.lua51 import LuaRuntime

root = Path(__file__).resolve().parents[1]
shell = root / "src" / "MiniQoL"
from scope import check_scope
check_scope(root, Path(sys.argv[1]) if len(sys.argv) > 1 else None)
runtime = LuaRuntime(unpack_returned_tuples=True)
runtime.execute((root / "tests/runtime.lua").read_text(), str(shell).replace("\\", "/"))
ui = LuaRuntime(unpack_returned_tuples=True)
ui.execute((root / "tests/ui.lua").read_text(), str(shell).replace("\\", "/"))
dialogue = LuaRuntime(unpack_returned_tuples=True)
dialogue.execute((root / "tests/dialogue.lua").read_text(), str(shell).replace("\\", "/"))

mixins = LuaRuntime(unpack_returned_tuples=True)
package = Path(sys.argv[1]) if len(sys.argv) > 1 else root / "MiniQoL"
mixins.execute((root / "tests/native_mixins.lua").read_text(), str(package).replace("\\", "/"))

memory = LuaRuntime(unpack_returned_tuples=True)
memory.execute((root / "tests/map_memory.lua").read_text(), str(package).replace("\\", "/"))

share = LuaRuntime(unpack_returned_tuples=True)
share.execute((root / "tests/waypoint_share.lua").read_text(), str(package).replace("\\", "/"))

if len(sys.argv) > 1:
    package = Path(sys.argv[1])
    sys.path.insert(0, str(root / "tools"))
    from build import read_toc, validate_entries
    metadata, entries = read_toc(package / "MiniQoL.toc")
    count = validate_entries(package, entries)
    compiler = LuaRuntime(encoding=None, unpack_returned_tuples=True)
    compile_lua = compiler.eval(b"function(source, name) local chunk, reason = loadstring(source, name); return chunk ~= nil, reason end")
    failures, checked = [], 0
    for path in package.rglob("*.lua"):
        # Compile every bundled source, including optional load-on-demand modules.
        ok, reason = compile_lua(path.read_bytes().removeprefix(b"\xef\xbb\xbf"), str(path.relative_to(package)).encode())
        checked += 1
        if not ok:
            failures.append((str(path.relative_to(package)), reason.decode("utf-8", errors="replace")))
    print(f"Validated {count} selected source references; compiled {checked} Lua files")
    for path, reason in failures[:30]:
        print(path, reason)
    if failures:
        raise SystemExit(f"{len(failures)} syntax errors")
    snapshot = package / "LegacyProfiles.lua"
    if snapshot.exists():
        migration_runtime = LuaRuntime(encoding=None, unpack_returned_tuples=True)
        migration_runtime.execute(b"UnitName=function() return 'MiniQoLTest' end; GetRealmName=function() return 'TestRealm' end; WayfinderDB={existingProfile=true}")
        migration_runtime.execute(snapshot.read_bytes())
        assert migration_runtime.eval(b"WayfinderDB.existingProfile"), "Existing profiles were overwritten"
        migration_runtime.execute(b"BugSackDB=nil")
        migration_runtime.execute(snapshot.read_bytes())
        assert migration_runtime.eval(b"BugSackDB == nil"), "Migration reintroduced removed configuration"
        print("Private profile migration preserves existing values and runs once")
