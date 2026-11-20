from pathlib import Path
import sys
from lupa.lua51 import LuaRuntime

root = Path(__file__).resolve().parents[1]
shell = root / "src" / "MiniQoL"
from scope import check_scope
check_scope(root, Path(sys.argv[1]) if len(sys.argv) > 1 else None)
runtime = LuaRuntime(unpack_returned_tuples=True)
runtime.execute((root / "tests/runtime.lua").read_text(), str(shell).replace("\\", "/"))
gearwise = (Path(sys.argv[1]) / "Modules" if len(sys.argv) > 1 else root / "src" / "Modules") / "Gearwise"
ui = LuaRuntime(unpack_returned_tuples=True)
ui.execute((root / "tests/ui.lua").read_text(), str(shell).replace("\\", "/"), str(gearwise).replace("\\", "/"))
dialogue = LuaRuntime(unpack_returned_tuples=True)
dialogue.execute((root / "tests/dialogue.lua").read_text(), str(shell).replace("\\", "/"))

mixins = LuaRuntime(unpack_returned_tuples=True)
package = Path(sys.argv[1]) if len(sys.argv) > 1 else root / "MiniQoL"
mixins.execute((root / "tests/native_mixins.lua").read_text(), str(package).replace("\\", "/"))

memory = LuaRuntime(unpack_returned_tuples=True)
memory.execute((root / "tests/map_memory.lua").read_text(), str(package).replace("\\", "/"))

pins = LuaRuntime(unpack_returned_tuples=True)
pins.execute((root / "tests/map_pins.lua").read_text(), str(package).replace("\\", "/"))

services = LuaRuntime(unpack_returned_tuples=True)
services.execute((root / "tests/service_pins.lua").read_text(), str(package).replace("\\", "/"))

seeds = LuaRuntime(unpack_returned_tuples=True)
seeds.execute((root / "tests/seeds.lua").read_text(), str(package).replace("\\", "/"))

cities = LuaRuntime(unpack_returned_tuples=True)
cities.execute((root / "tests/city_layers.lua").read_text(), str(package).replace("\\", "/"))

tracking = LuaRuntime(unpack_returned_tuples=True)
tracking.execute((root / "tests/minimap_tracking.lua").read_text(), str(package).replace("\\", "/"))

fishing = LuaRuntime(unpack_returned_tuples=True)
fishing.execute((root / "tests/fishing.lua").read_text(), str(shell).replace("\\", "/"))

alt_gear = LuaRuntime(unpack_returned_tuples=True)
alt_gear.execute((root / "tests/alt_gear.lua").read_text(), str(shell).replace("\\", "/"))

share = LuaRuntime(unpack_returned_tuples=True)
share.execute((root / "tests/waypoint_share.lua").read_text(), str(package).replace("\\", "/"))

tomtom = LuaRuntime(unpack_returned_tuples=True)
tomtom.execute((root / "tests/tomtom.lua").read_text(), str(package).replace("\\", "/"))

corpse = LuaRuntime(unpack_returned_tuples=True)
corpse.execute((root / "tests/corpse.lua").read_text(), str(package).replace("\\", "/"))

polestar = LuaRuntime(unpack_returned_tuples=True)
polestar.execute((root / "tests/polestar.lua").read_text(), str(package).replace("\\", "/"))

quest_waypoints = LuaRuntime(unpack_returned_tuples=True)
quest_waypoints.execute((root / "tests/quest_waypoints.lua").read_text(), str(package).replace("\\", "/"))

background_jobs = LuaRuntime(unpack_returned_tuples=True)
background_jobs.execute((root / "tests/background_jobs.lua").read_text(), str(package).replace("\\", "/"))

pin_guard = LuaRuntime(unpack_returned_tuples=True)
pin_guard.execute((root / "tests/pin_guard.lua").read_text(), str(package).replace("\\", "/"))

convergences = LuaRuntime(unpack_returned_tuples=True)
convergences.execute((root / "tests/convergences.lua").read_text(), str(package).replace("\\", "/"))

map_tracking = LuaRuntime(unpack_returned_tuples=True)
map_tracking.execute((root / "tests/map_tracking.lua").read_text(), str(package).replace("\\", "/"))

arrow_snap = LuaRuntime(unpack_returned_tuples=True)
arrow_snap.execute((root / "tests/arrow_snap.lua").read_text(), str(package).replace("\\", "/"))

sidegrades = LuaRuntime(unpack_returned_tuples=True)
sidegrades.execute((root / "tests/sidegrades.lua").read_text(), str(gearwise).replace("\\", "/"), str(shell).replace("\\", "/"))

upgrades = LuaRuntime(unpack_returned_tuples=True)
upgrades.execute((root / "tests/upgrades.lua").read_text(), str(gearwise).replace("\\", "/"), str(shell).replace("\\", "/"))

for name in ("builds", "gear_events", "items"):
    LuaRuntime(unpack_returned_tuples=True).execute(
        (root / f"tests/{name}.lua").read_text(), str(gearwise).replace("\\", "/"), str(shell).replace("\\", "/"))

peddler = LuaRuntime(unpack_returned_tuples=True)
peddler.execute((root / "tests/peddler.lua").read_text(), str(gearwise.parent / "Peddler").replace("\\", "/"))

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
