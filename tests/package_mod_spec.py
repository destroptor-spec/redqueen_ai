"""The uploadable payload must contain everything the game loads, and nothing else.

The repository is a development tree: match archives, contracts, drivers and
notes outnumber the mod itself roughly twenty to one by size. `package-mod.sh`
ships an allowlist rather than an exclusion list, so the failure mode to guard
is not "something extra got in" -- it is "the allowlist missed something the
game imports".
"""
import re
import subprocess
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PACKAGER = ROOT / "scripts" / "package-mod.sh"
MOD_ROOT = "/mods/TheRedQueen/"


def payload_entries():
    """The allowlist, read from the packager rather than duplicated here."""
    text = PACKAGER.read_text(encoding="utf-8")
    block = re.search(r"^payload=\(\n(.*?)^\)$", text, re.S | re.M)
    assert block, "package-mod.sh must declare a payload=( ... ) allowlist"
    return [line.strip() for line in block.group(1).splitlines() if line.strip()]


class PackagePayload(unittest.TestCase):
    def setUp(self):
        self.payload = payload_entries()

    def test_every_payload_entry_exists(self):
        for entry in self.payload:
            self.assertTrue((ROOT / entry).exists(), f"payload entry missing: {entry}")

    def test_every_mod_import_resolves_inside_the_payload(self):
        """An import of a file the archive does not carry is a broken upload."""
        roots = [ROOT / entry for entry in self.payload]
        missing = []
        for source in list(ROOT.glob("lua/**/*.lua")) + list(ROOT.glob("hook/**/*.lua")):
            for match in re.finditer(r'import\(\s*"([^"]+)"', source.read_text(encoding="utf-8")):
                path = match.group(1)
                if not path.startswith(MOD_ROOT):
                    continue  # a native FAF module, supplied by the game
                target = ROOT / path[len(MOD_ROOT):]
                if not target.exists():
                    missing.append(f"{source.relative_to(ROOT)} -> {path} (no such file)")
                elif not any(
                    target == root or root in target.parents for root in roots
                ):
                    missing.append(f"{source.relative_to(ROOT)} -> {path} (outside the payload)")
        self.assertEqual(missing, [], "imports not carried by the archive: " + "; ".join(missing))

    def test_the_icon_is_carried(self):
        metadata = (ROOT / "mod_info.lua").read_text(encoding="utf-8")
        icon = re.search(r'^icon = "([^"]+)"', metadata, re.M)
        if not icon:
            self.skipTest("no icon declared")
        self.assertTrue(icon.group(1).startswith(MOD_ROOT), "the icon must live inside the mod")
        self.assertTrue((ROOT / icon.group(1)[len(MOD_ROOT):]).is_file(), "declared icon is missing")

    def test_every_import_agrees_on_the_mod_folder_name(self):
        """The uploader records the folder name, and every import is absolute.

        Ship under any other name and each `/mods/<name>/...` path resolves to
        nothing -- a mod that installs and then fails on first use, which is
        harder to diagnose than one that fails to install.
        """
        prefixes = set()
        for source in list(ROOT.glob("lua/**/*.lua")) + list(ROOT.glob("hook/**/*.lua")):
            for match in re.finditer(r'import\(\s*"/mods/([^/"]+)/', source.read_text(encoding="utf-8")):
                prefixes.add(match.group(1))
        self.assertEqual(
            prefixes, {"TheRedQueen"},
            "every import must be rooted at /mods/TheRedQueen/, found: " + ", ".join(sorted(prefixes)),
        )

    def test_the_packager_ships_that_same_folder_name(self):
        text = PACKAGER.read_text(encoding="utf-8")
        name = re.search(r'^name="([^"]+)"', text, re.M)
        self.assertIsNotNone(name, "package-mod.sh must declare the mod folder name")
        self.assertEqual(name.group(1), "TheRedQueen")
        self.assertIn(
            'prefixes[0]}" != "$name', text,
            "the packager must cross-check the folder name against the imports",
        )

    def test_development_trees_are_not_shipped(self):
        """38 MB of match archives live under docs/. None of it is the mod."""
        for forbidden in ("docs", "tests", "scripts", ".git", ".claude"):
            self.assertNotIn(forbidden, self.payload, f"{forbidden} must never be packaged")

    def test_the_readme_release_label_matches_the_version(self):
        version = re.search(r"^version = (\d+)", (ROOT / "mod_info.lua").read_text(encoding="utf-8"), re.M)
        readme = (ROOT / "README.md").read_text(encoding="utf-8")
        labels = set(re.findall(r"Release `V(\d+)`", readme))
        if labels:
            self.assertEqual(
                labels, {version.group(1)},
                "README ships to players and its release label drifted from mod_info.lua",
            )

    def test_the_packager_emits_a_directory_not_only_an_archive(self):
        """The FAF uploader selects a directory containing mod_info.lua."""
        text = PACKAGER.read_text(encoding="utf-8")
        self.assertIn("UPLOAD THIS DIRECTORY", text,
                      "the packager must name the directory to upload")
        self.assertIn('rm -rf -- "$root"', text,
                      "the directory must be rebuilt, or a file from an earlier "
                      "version is uploaded with the rest")

    def test_the_packager_refuses_a_failing_tree(self):
        text = PACKAGER.read_text(encoding="utf-8")
        self.assertIn("validate.sh", text, "the packager must not archive an unvalidated tree")


if __name__ == "__main__":
    unittest.main()
