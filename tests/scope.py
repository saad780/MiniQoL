"""Prevent unrelated installed addons from being bundled or managed."""
from pathlib import Path
from tempfile import TemporaryDirectory
import sys

EXPECTED = {"Peddler", "Gearwise", "Wayfinder", "XPCounter"}


def check_scope(root, package=None):
    sys.path.insert(0, str(root / "tools"))
    from build import COMPONENTS, build, migration

    assert set(COMPONENTS) == EXPECTED
    assert {p.name for p in (root / "src/Modules").iterdir() if p.is_dir()} == EXPECTED
    if package:
        assert {p.name for p in (package / "Modules").iterdir() if p.is_dir()} == EXPECTED

    with TemporaryDirectory(prefix="miniqol-scope-") as temporary:
        fixture = Path(temporary)
        sources = fixture / "sources"
        (sources / "UnrelatedAddon").mkdir(parents=True)
        destination = fixture / "output"
        try:
            build(sources, fixture / "no-settings", destination)
        except ValueError as error:
            assert "Out-of-scope" in str(error)
        else:
            raise AssertionError("The builder accepted an unrelated addon")
        assert not destination.exists(), "Rejected builds must not write output"

        (destination / "MiniQoL/Modules/UnrelatedAddon").mkdir(parents=True)
        try:
            build(root / "src/Modules", fixture / "no-settings", destination, refresh=True)
        except ValueError as error:
            assert "out-of-scope" in str(error)
        else:
            raise AssertionError("Refreshing retained an unrelated addon")
        account = fixture / "account"
        flags = account / "TestRealm/TestCharacter/AddOns.txt"
        flags.parent.mkdir(parents=True)
        retired = "\n".join(name + ": disabled" for name in sorted(EXPECTED))
        flags.write_text("MiniQoL: enabled\n" + retired)
        modules = {name: {"metadata": {}} for name in EXPECTED}
        _, states = migration(account, modules)
        assert states["TestCharacter"] == {}, "Retired standalone flags disabled bundled modules"
        flags.write_text("MiniQoL: disabled\n" + retired)
        _, states = migration(account, modules)
        assert states["TestCharacter"] == dict.fromkeys(EXPECTED, False), "First install lost standalone preferences"
    print("Exact four-component scope and rejection of unrelated addons passed")
