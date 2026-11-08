"""Build a personal, standalone MiniQoL package from the local installation.

Only Peddler, Gearwise, Wayfinder and XPCounter are accepted as build inputs.
Original authorship notices, licences and individual manifests are retained.
"""
from __future__ import annotations

import argparse
import json
import re
import shutil
from pathlib import Path
import xml.etree.ElementTree as ET
from lupa.lua51 import LuaRuntime

LUA_COMPILER = LuaRuntime(encoding=None, unpack_returned_tuples=True).eval(
    b"function(source) local fn, err = loadstring(source); return fn ~= nil, err end")

XP_BRIDGE = b'''
-- Mini QoL adapter. XP Counter has no settings window of its own; the Mini QoL
-- panel drives the floating text through these.
function addon.MiniQoLSetPopups(value)
    if not db then return end
    db.popupsEnabled = not not value
    if not value then setMoving(false) end
end

function addon.MiniQoLStartMoving()
    setMoving(true)
end

function addon.MiniQoLPreview()
    preview()
end

function addon.MiniQoLResetPosition()
    if not db then return end
    db.x, db.y = 0, 180
    popup:ClearAllPoints()
    popup:SetPoint("CENTER", UIParent, "CENTER", db.x, db.y)
    if moving then preview() end
end
'''

ROOT = Path(__file__).resolve().parents[1]
SHELL = ROOT / "src" / "MiniQoL"
COMPONENTS = frozenset({"Peddler", "Gearwise", "Wayfinder", "XPCounter"})
DEFAULT_ADDONS = ROOT / "src" / "Modules"
DEFAULT_ACCOUNT = ROOT / "build" / "no-user-settings"


def lua(value):
    if value is None:
        return "nil"
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, float)):
        return str(value)
    if isinstance(value, str):
        return '"' + "".join(
            "\\\\" if c == "\\" else '\\"' if c == '"' else f"\\{ord(c):03d}" if ord(c) < 32 else c
            for c in value
        ) + '"'
    if isinstance(value, list):
        return "{" + ",".join(map(lua, value)) + "}"
    return "{" + ",".join(f"[{lua(k)}]={lua(v)}" for k, v in value.items()) + "}"


def read_toc(path):
    metadata, entries = {}, []
    for line in path.read_text(encoding="utf-8-sig").splitlines():
        line = line.strip()
        match = re.match(r"##\s*([^:]+):\s*(.*)", line)
        if match:
            value = match[2].strip()
            if re.search(r"\[ExcludeLoadGameType\s+[^\]]*\bcamelot\b", value, re.I):
                continue
            metadata[match[1].strip()] = re.sub(r"\s*\[(?:Allow|Exclude)Load\w+\b.*$", "", value)
        elif line and not line.startswith("#"):
            entries.append(line)
    return metadata, entries


def select_toc(folder):
    choices = []
    for path in folder.glob("*.toc"):
        metadata, entries = read_toc(path)
        if "16001" not in metadata.get("Interface", "").split(",") and not re.search(r"\b16001\b", metadata.get("Interface", "")):
            continue
        suffix = path.stem.lower()
        score = 3 if suffix.endswith(("_camelot", "-camelot")) else 2 if suffix.endswith("_forever") else 1
        choices.append((score, path, metadata, entries))
    if not choices:
        fallback = next((p for p in folder.glob("*.toc") if p.stem.lower() == folder.name.lower()), None)
        if fallback:
            metadata, entries = read_toc(fallback)
            return 0, fallback, metadata, entries
        raise ValueError(f"No usable manifest: {folder.name}")
    return max(choices, key=lambda c: (c[0], c[1].name))


def names(value):
    return [n for n in re.split(r"[,\s]+", re.sub(r"\s*\[(?:Allow|Exclude)Load\w+\b.*$", "", value or "")) if n]


def dependency_order(modules):
    result, visiting, complete = [], set(), set()

    def visit(name):
        if name in complete or name in visiting:
            return
        visiting.add(name)
        m = modules[name]
        for dependency in m["dependencies"] + m["optional"]:
            if dependency in modules:
                visit(dependency)
        visiting.remove(name)
        complete.add(name)
        result.append(name)

    for name in sorted(modules, key=str.lower):
        visit(name)
    positions = {name: i for i, name in enumerate(result)}
    for name, module in modules.items():
        for dependency in module["dependencies"]:
            if dependency in positions and positions[dependency] >= positions[name]:
                raise ValueError(f"Required dependency cycle: {dependency} -> {name}")
    return result


def rewrite_paths(data, module_names):
    # Handle Lua escaped strings, XML paths and slash-separated media paths.
    for separator in (b"\\\\", b"\\", b"/"):
        prefix = separator.join((b"Interface", b"AddOns")) + separator
        canonical = {name.lower().encode(): name.encode() for name in module_names}
        options = b"|".join(re.escape(name.encode()) for name in sorted(module_names, key=len, reverse=True))
        pattern = re.compile(re.escape(prefix) + b"(" + options + rb")(?=[\\/\"'\s<]|$)", re.I)
        data = pattern.sub(lambda m: prefix + b"MiniQoL" + separator + b"Modules" + separator + canonical[m[1].lower()], data)
        # Dynamically assembled roots, e.g. "Interface\\AddOns\\" .. addonName.
        pattern = re.compile(re.escape(prefix) + rb"(?=[\"'\]]|%[sd])", re.I)
        data = pattern.sub(lambda _: prefix + b"MiniQoL" + separator + b"Modules" + separator, data)
    return data


def migrate_file(path, globals_to_import, module, character=False):
    if not path.is_file() or not globals_to_import:
        return ""
    source = path.read_text(encoding="utf-8-sig", errors="surrogateescape")
    declarations = ",".join(globals_to_import)
    results = ",".join(f"[{lua(n)}]={n}" for n in globals_to_import)
    tracking = "characterImports" if character else "accountImports"
    return f"if not {tracking}[{lua(module)}] then\nlocal function snapshot()\nlocal {declarations}\n{source}\nreturn {{{results}}}\nend\nimport(snapshot())\n{tracking}[{lua(module)}] = true\nend\n"


def migration(account, modules):
    header = "-- PRIVATE profile snapshot. Generated locally; never publish this file.\n" if account.is_dir() else "-- Defaults-only migration initializer. No personal settings are embedded.\n"
    text = [header,
            "MiniQoLDB = type(MiniQoLDB) == 'table' and MiniQoLDB or {}\n",
            "MiniQoLDB.migratedModules = MiniQoLDB.migratedModules or {}\n",
            "MiniQoLDB.migratedCharacters = MiniQoLDB.migratedCharacters or {}\n",
            "local accountImports = MiniQoLDB.migratedModules\n",
            "local characterKey = (UnitName('player') or '') .. '|' .. (GetRealmName() or '')\n",
            "MiniQoLDB.migratedCharacters[characterKey] = MiniQoLDB.migratedCharacters[characterKey] or {}\n",
            "local characterImports = MiniQoLDB.migratedCharacters[characterKey]\n",
            "local function import(values) for key, value in pairs(values) do if _G[key] == nil then _G[key] = value end end end\n"]
    states = {}
    for name, module in modules.items():
        text.append(migrate_file(account / "SavedVariables" / f"{name}.lua", names(module["metadata"].get("SavedVariables")), name))
    if account.is_dir():
        for addon_list in sorted(account.glob("*/*/AddOns.txt")):
            char = addon_list.parent.name
            state = {}
            lines = addon_list.read_text(encoding="utf-8-sig").splitlines()
            # The installer disables the retired standalone folders. On updates,
            # those flags must not disable their embedded replacements.
            already_installed = any(re.fullmatch(r"MiniQoL:\s*enabled\s*", line) for line in lines)
            for line in lines:
                match = re.match(r"(.+?):\s*(enabled|disabled)", line)
                if match and match[1] in modules and not already_installed:
                    state[match[1]] = match[2] == "enabled"
            for alias in {char, char.replace("-", " "), char.replace("-", "")}:
                states[alias] = state
            text.append(f"if UnitName('player') == {lua(char)} or UnitName('player') == {lua(char.replace('-', ' '))} or UnitName('player') == {lua(char.replace('-', ''))} then\n")
            for name, module in modules.items():
                text.append(migrate_file(addon_list.parent / "SavedVariables" / f"{name}.lua", names(module["metadata"].get("SavedVariablesPerCharacter")), name, True))
            text.append("end\n")
    return "".join(text), states


def resolve_case(path):
    # Windows handles casing itself. Also support tests on case-sensitive systems.
    if path.exists():
        return path
    if path.parent.exists():
        return next((p for p in path.parent.iterdir() if p.name.lower() == path.name.lower()), path)
    return path


def absolute_xml_includes(data, original_file, addon_root, all_addons):
    def replace(match):
        requested = match[2].decode("utf-8").replace("\\", "/")
        if requested.lower().startswith("interface/"):
            return match[0]
        candidates = [original_file.parent / requested, addon_root / requested]
        chosen = None
        for candidate in candidates:
            if "[" in requested:
                pattern = candidate.name.replace("[TextLocale]", "*").replace("[GameLocale]", "*")
                if candidate.parent.exists() and list(candidate.parent.glob(pattern)):
                    chosen = candidate
                    break
            elif resolve_case(candidate).is_file():
                chosen = resolve_case(candidate)
                break
        if chosen is None:
            return match[0]
        relative = chosen.resolve().relative_to(all_addons.resolve())
        replacement = "Interface\\AddOns\\MiniQoL\\Modules\\" + str(relative).replace("/", "\\")
        return match[1] + replacement.encode() + match[3]
    return re.sub(rb'(<(?:Script|Include)\b[^>]*\bfile=["\x27])([^"\x27]+)(["\x27])', replace, data)


def validate_entries(output, entries):
    """Walk selected TOCs/XML includes and verify every concrete referenced source."""
    visited, missing = set(), []
    def visit(relative):
        normalized = re.sub(r"\s*\[(?:Allow|Exclude)Load\w+\b.*$", "", relative).replace("\\", "/")
        if "[" in normalized:  # Client locale substitutions are checked individually below.
            pattern = re.sub(r"\[\w+\]", "*", normalized)
            if not list(output.glob(pattern)):
                missing.append(normalized)
            return
        path = resolve_case(output / normalized)
        if path in visited:
            return
        visited.add(path)
        if not path.is_file():
            missing.append(normalized)
            return
        if path.suffix.lower() == ".xml":
            try:
                xml = path.read_bytes()
                if b"xsi:" in xml and b"xmlns:xsi=" not in xml:
                    xml = re.sub(rb"<Ui\b", b'<Ui xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"', xml, count=1)
                tree = ET.ElementTree(ET.fromstring(xml))
            except ET.ParseError as exc:
                raise ValueError(f"Invalid XML {path}: {exc}") from exc
            for node in tree.iter():
                if node.tag.rsplit("}", 1)[-1] in {"Include", "Script"} and node.get("file"):
                    child = node.get("file").replace("\\", "/")
                    if child.lower().startswith("interface/addons/miniqol/"):
                        visit(child[len("Interface/AddOns/MiniQoL/"):])
                    else:
                        visit(str(path.parent.relative_to(output) / child))
    for entry in entries:
        visit(entry)
    if missing:
        raise ValueError("Missing source files:\n" + "\n".join(missing[:40]))
    return len(visited)


def build(addons, account, destination, refresh=False):
    output = destination / "MiniQoL"
    if output.exists() and not refresh:
        raise ValueError(f"Use a fresh output directory; refusing to overwrite {output}")
    modules = {}
    sources = {}
    unexpected = {p.name for p in addons.iterdir() if p.is_dir()} - COMPONENTS
    if unexpected:
        raise ValueError("Out-of-scope addon folders: " + ", ".join(sorted(unexpected)))
    existing_modules = output / "Modules"
    if existing_modules.is_dir() and any(p.is_dir() and p.name not in COMPONENTS for p in existing_modules.iterdir()):
        raise ValueError("The destination contains out-of-scope addons. Use a clean output directory.")
    for folder in sorted(addons.iterdir()):
        if not folder.is_dir() or folder.name.startswith("Blizzard_") or folder.name == "MiniQoL":
            continue
        flavor_score, toc, metadata, entries = select_toc(folder)
        modules[folder.name] = {"metadata": metadata, "dependencies": names(metadata.get("Dependencies", metadata.get("RequiredDeps"))),
                                "optional": names(metadata.get("OptionalDeps")), "defaultEnabled": flavor_score > 0}
        sources[folder.name] = (folder, toc, entries)
    if not modules:
        raise ValueError("No component sources found. Use src/Modules with the four approved components.")
    if set(modules) != COMPONENTS:
        raise ValueError("The build must contain exactly Peddler, Gearwise, Wayfinder and XPCounter.")
    order = dependency_order(modules)
    output.mkdir(parents=True, exist_ok=refresh)
    shutil.copytree(SHELL, output, dirs_exist_ok=True)
    for module in modules.values():
        module["metadata"] = {key: rewrite_paths(value.encode("utf-8"), modules).decode("utf-8")
                              for key, value in module["metadata"].items()}
    migration_text, states = migration(account, modules)
    migration_text = rewrite_paths(migration_text.encode("utf-8", errors="surrogateescape"), modules).decode("utf-8", errors="surrogateescape")
    (output / "LegacyProfiles.lua").write_text(migration_text, encoding="utf-8", errors="surrogateescape")
    (output / "CharacterStates.lua").write_text("MiniQoLCharacterStates = " + lua(states) + "\n", encoding="utf-8")
    manifest = {"modules": modules, "order": order}
    (output / "Manifest.lua").write_text("MiniQoLRuntime:Install(" + lua(manifest) + ", MiniQoLCharacterStates)\nMiniQoLCharacterStates = nil\nMiniQoL:Initialize()\n", encoding="utf-8")
    entries = ["Core.lua", "Theme.lua", "Runtime.lua", "LegacyProfiles.lua", "CharacterStates.lua", "Manifest.lua"]
    bindings = []
    credits = [(ROOT / "THIRD_PARTY.md").read_text(encoding="utf-8"),
               "\n## Bundled component versions\n"]
    for notice in ("LICENSE", "COPYRIGHT", "THIRD_PARTY.md"):
        shutil.copy2(ROOT / notice, output / notice)
    lua_count = 0
    for name in order:
        folder, toc, source_entries = sources[name]
        target = output / "Modules" / name
        def copy_input(source, dest):
            dest = Path(dest)
            if refresh and dest.exists() and Path(source).suffix.lower() not in {".lua", ".xml", ".toc"} and dest.stat().st_size == Path(source).stat().st_size:
                return str(dest)
            return shutil.copy2(source, dest)
        shutil.copytree(folder, target, dirs_exist_ok=refresh, copy_function=copy_input,
                        ignore=shutil.ignore_patterns(".git", "__pycache__", "*.pyc"))
        for file in target.rglob("*"):
            if not file.is_file() or file.suffix.lower() not in {".lua", ".xml", ".toc"}:
                continue
            data = file.read_bytes().removeprefix(b"\xef\xbb\xbf")
            if file.suffix.lower() == ".xml":
                data = absolute_xml_includes(data, folder / file.relative_to(target), folder, addons)
            data = rewrite_paths(data, modules)
            if file.suffix.lower() == ".lua":
                if name == "XPCounter" and file.name == "Popup.lua":
                    data += XP_BRIDGE
                original = data
                data = (f"-- Mini QoL packaging adapter; upstream source and credits follow.\nMiniQoLRuntime:Execute({lua(name)}, function(...)\n".encode()
                        + original + b"\nend)\n")
                if not LUA_COMPILER(data)[0]:
                    if not LUA_COMPILER(original)[0]:
                        raise ValueError(f"Original source does not compile: {file}")
                    delimiter = b"="
                    while b"]" + delimiter + b"]" in original:
                        delimiter += b"="
                    chunk_name = "@Interface/AddOns/MiniQoL/" + str(file.relative_to(output)).replace("\\", "/")
                    data = (f"-- Mini QoL adapter for a source file at the Lua compiler's local-variable limit.\nMiniQoLRuntime:ExecuteSource({lua(name)}, ".encode()
                            + b"[" + delimiter + b"[\n" + original + b"]" + delimiter + b"], " + lua(chunk_name).encode() + b")\n")
                lua_count += 1
            elif file.suffix.lower() == ".xml":
                guard = f"if not MiniQoLRuntime:CanLoad({lua(name)}) then return end; ".encode()
                hidden_guard = f"if not MiniQoLRuntime:CanLoad({lua(name)}) then self:Hide(); if self.UnregisterAllEvents then self:UnregisterAllEvents() end; return end; ".encode()
                tracking = f"MiniQoLRuntime:TrackFrame(self, {lua(name)}); ".encode()
                data = re.sub(rb"(<(On\w+)\b[^>]*>\s*(?:<!\[CDATA\[)?)",
                              lambda m: m[1] + (hidden_guard if m[2] in {b"OnLoad", b"OnShow"} else guard)
                              + (tracking if m[2] == b"OnLoad" else b""), data)
                data = re.sub(rb"(<Script\b(?![^>]*\bfile=)[^>]*>)([\s\S]*?)(</Script>)",
                              lambda m: m[1] + f"MiniQoLRuntime:Execute({lua(name)}, function(...)\n".encode()
                              + m[2] + b"\nend)" + m[3], data)
            file.write_bytes(data)
        for entry in source_entries:
            entries.append(f"Modules\\{name}\\{entry}")
        complete = target / "_MiniQoLComplete.lua"
        complete.write_text(f"MiniQoLRuntime:Complete({lua(name)})\n", encoding="utf-8")
        entries.append(str(complete.relative_to(output)).replace("/", "\\"))
        binding_file = folder / "Bindings.xml"
        if binding_file.exists():
            tree = ET.fromstring(rewrite_paths(binding_file.read_bytes(), modules))
            bindings.extend(list(tree))
        meta = modules[name]["metadata"]
        licence_files = [str(p.relative_to(target)) for p in target.rglob("*") if p.is_file() and re.search(r"licen[sc]e|copying", p.name, re.I)]
        credits.append(f"\n## {name}\n\nAuthor: {meta.get('Author', 'See retained source headers')}\n\nVersion: {meta.get('Version', 'unknown')}\n\nManifest: Modules/{name}/{toc.name}\n\nLicences: {', '.join(licence_files) or 'See retained source headers; no root licence supplied'}\n")
    entries += ["Dialogue.lua", "Integrations.lua", "Panel.lua", "Minimap.lua"]
    saved, per_char = {"MiniQoLDB"}, set()
    for m in modules.values():
        saved.update(names(m["metadata"].get("SavedVariables")))
        per_char.update(names(m["metadata"].get("SavedVariablesPerCharacter")))
    if saved & per_char:
        raise ValueError(f"Saved variable scope collision: {saved & per_char}")
    external_dependencies = sorted({dependency for m in modules.values() for dependency in m["dependencies"] + m["optional"] if dependency not in modules})
    dependency_line = "## OptionalDeps: " + ", ".join(external_dependencies) + "\n" if external_dependencies else ""
    shell_version = read_toc(SHELL / "MiniQoL.toc")[0]["Version"]
    toc_text = ("## Interface: 16001\n## Title: Mini QoL\n## Author: saad780 and credited module authors\n"
                f"## Version: {shell_version}\n## X-License: GPL-3.0-only\n## Notes: Standalone consolidation for WoW Forever.\n"
                "## LoadSavedVariablesFirst: 1\n## IconTexture: Interface\\Icons\\INV_Misc_Gear_01\n"
                + dependency_line
                + "## SavedVariables: " + ", ".join(sorted(saved)) + "\n"
                "## SavedVariablesPerCharacter: " + ", ".join(sorted(per_char)) + "\n\n" + "\n".join(entries) + "\n")
    (output / "MiniQoL.toc").write_text(toc_text, encoding="utf-8")
    if bindings:
        root = ET.Element("Bindings")
        root.extend(bindings)
        ET.ElementTree(root).write(output / "Bindings.xml", encoding="utf-8", xml_declaration=True)
    (output / "CREDITS.md").write_text("".join(credits), encoding="utf-8")
    (destination / "profile-contract.json").write_text(json.dumps({name: {"metadata": {
        key: value for key, value in m["metadata"].items() if key in {"SavedVariables", "SavedVariablesPerCharacter"}}}
        for name, m in modules.items()}), encoding="utf-8")
    source_files = validate_entries(output, entries)
    report = {"modules": len(modules), "wrapped_lua_files": lua_count, "selected_source_files": source_files,
              "order": order, "saved_variables": len(saved), "character_saved_variables": len(per_char),
              "game_dependencies": external_dependencies,
              "private_profile_snapshot": account.is_dir(), "source_addons": str(addons), "output": str(output)}
    (destination / "build-report.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(json.dumps({k: v for k, v in report.items() if k != "order"}, indent=2))
    return report


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--addons", type=Path, default=DEFAULT_ADDONS)
    parser.add_argument("--account", type=Path, default=DEFAULT_ACCOUNT)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--refresh", action="store_true", help="Refresh an existing generated build from original sources")
    args = parser.parse_args()
    build(args.addons, args.account, args.output, args.refresh)
