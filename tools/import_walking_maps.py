"""Vendor the walking engine and checked maps from Polestar 0.4.2.1."""

import argparse
import hashlib
import json
from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[1]
VENDOR = ROOT / "src/Modules/Wayfinder/Vendor/PolestarWalking"
VERSION = "0.4.2.1"
ENGINE = ("Routing/Costs.lua", "Routing/PathGrid.lua", "Routing/Path.lua", "Routing/PathJobs.lua", "API.lua")
GUIDE = ("Nav/Follow.lua", "Nav/Danger.lua", "Maps/ZoneLevels.lua")


def namespace(source):
    source = source.removeprefix(b"\xef\xbb\xbf")
    data, selects = re.subn(rb"^(\s*local ns\s*=\s*)select\(\s*2\s*,\s*\.\.\.\s*\)",
                           rb"\1(select(2, ...)).Walking", source, flags=re.M)
    data, varargs = re.subn(rb"^([ \t]*local (?:ADDON|_)\s*,\s*ns\s*=\s*\.\.\.)",
                           rb"\1\nns = ns.Walking", data, flags=re.M)
    if not (selects or varargs):
        data = b"local ns = (select(2, ...)).Walking\n" + data
    return (b"-- Adapted for the Mini QoL namespace (2026-11-22). See UPSTREAM-CREDITS.md.\n"
            + data.replace(b"PolestarPathData", b"ns.PathData")
                .replace(b"PolestarNavChokepoints", b"ns.Chokepoints"))


def import_walking(addons):
    pack = addons / "Polestar_Nav"
    toc = (pack / "Polestar_Nav.toc").read_text(encoding="utf-8-sig")
    if not re.search(rf"^## Version: {re.escape(VERSION)}\s*$", toc, re.M):
        raise ValueError(f"Expected the Polestar {VERSION} walking pack")
    manifest = json.loads((pack / "PACK.json").read_bytes())
    sources = {}
    for name, expected in manifest["files"].items():
        relative = Path(name)
        data = ((pack if relative.parts[0] == "Nav" else addons) / relative).read_bytes()
        if hashlib.sha256(data).hexdigest() != expected:
            raise ValueError(f"Map data does not match upstream manifest: {name}")
        sources[f"Maps/{relative.name}"] = namespace(data)

    for name in ENGINE:
        source = namespace((pack / name).read_bytes())
        if name == "Routing/Costs.lua":
            source = source.replace(b"\nPolestar_NavCosts = Costs", b"")
        elif name == "Routing/PathGrid.lua":
            start = source.index(b"-- A map's part addon, loaded once")
            stop = source.index(b"-- The directory is resident", start)
            source = source[:start] + b"""-- Wayfinder's map parts are already loaded from its own TOC.
local function EnsurePart(_, D)
	if D.part and not D.partReady then D.partReady = Whole(D) end
	return not D.part or D.partReady
end

""" + source[stop:]
        elif name == "Routing/Path.lua":
            source = source.replace(b"Polestar and Polestar.Nav and Polestar.Nav.danger", b"ns.Nav.danger")
            source = source.replace(b"Polestar and Polestar.Nav and Polestar.Nav.travel", b"ns.Nav.travel")
        elif name == "API.lua":
            source = source.replace(b"if whole and not D.part and", b"if whole and")
            source = source.replace(b"\nPolestar_NavEngine = Path", b"\nns.Nav.Path = Path")
        sources[name] = source

    sources["Trails.lua"] = namespace((pack / "Trails/Trails.lua").read_bytes())
    for name in GUIDE:
        source = namespace((addons / "Polestar" / name).read_bytes())
        if name == "Nav/Danger.lua":
            source += b"\n-- As in Polestar 0.4.2.1, hostile hubs affect cost without vetoing a walk.\nfunction Danger.Blocked() end\n"
        sources[Path(name).name] = source

    sources["LICENSE"] = (pack / "LICENSE").read_bytes()
    sources["UPSTREAM-CREDITS.md"] = (pack / "CREDITS.md").read_bytes()
    load_order = [name for name in sources if name.endswith(".lua")]
    xml = ['<Ui xmlns="http://www.blizzard.com/wow/ui/">']
    xml.extend(f'    <Script file="{name}"/>' for name in load_order)
    xml.append("</Ui>")
    sources["Walking.xml"] = ("\n".join(xml) + "\n").encode()
    for name, data in sources.items():
        file = VENDOR / name
        file.parent.mkdir(parents=True, exist_ok=True)
        file.write_bytes(data)
    print(f"Imported {len(load_order)} Lua files from Polestar {VERSION}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("addons", type=Path, help="AddOns directory or extracted Polestar release")
    import_walking(parser.parse_args().addons)
