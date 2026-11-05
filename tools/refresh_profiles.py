"""Refresh private profile migration after WoW exits, without rebuilding media."""
import argparse
import json
from pathlib import Path
from build import migration, lua, rewrite_paths, DEFAULT_ACCOUNT

parser = argparse.ArgumentParser()
parser.add_argument("build", type=Path)
parser.add_argument("--account", type=Path, default=DEFAULT_ACCOUNT)
args = parser.parse_args()
contract = json.loads((args.build / "profile-contract.json").read_text())
profile_source, states = migration(args.account, contract)
profile_source = rewrite_paths(profile_source.encode("utf-8", errors="surrogateescape"), contract).decode("utf-8", errors="surrogateescape")
package = args.build / "MiniQoL"
(package / "LegacyProfiles.lua").write_text(profile_source, encoding="utf-8", errors="surrogateescape")
(package / "CharacterStates.lua").write_text("MiniQoLCharacterStates = " + lua(states) + "\n", encoding="utf-8")
print("Refreshed private account and character profile snapshots.")
