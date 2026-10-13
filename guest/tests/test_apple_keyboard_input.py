#!/usr/bin/env python3
"""Run apple-keyboard-input.lua against fake cmdlines."""

from __future__ import annotations

from pathlib import Path
import shutil
import subprocess
import unittest


GUEST = Path(__file__).resolve().parents[1]
LUA = GUEST / "native-overlay/usr/share/try-omarchy/apple-keyboard-input.lua"
HARNESS = GUEST / "tests/apple_keyboard_input_harness.lua"


class AppleKeyboardInputTests(unittest.TestCase):
    def test_lua_geometry_token_parsing(self) -> None:
        lua = shutil.which("lua") or shutil.which("lua5.4") or shutil.which("luajit")
        if lua is None:
            self.skipTest(
                "lua is required to execute apple-keyboard-input.lua "
                "(install with: brew install lua)"
            )

        cases = {
            "root=/dev/vda rw": None,
            "root=/dev/vda tryomarchy.keyboard=iso": "applealu_iso",
            "tryomarchy.keyboard=ansi console=hvc0": "applealu_ansi",
            "xtryomarchy.keyboard=iso": None,
            "tryomarchy.keyboard=isoextra": None,
            "tryomarchy.keyboard=jis": "applealu_jis",
            "tryomarchy.keyboard=fr": None,
        }
        for cmdline, expected in cases.items():
            completed = subprocess.run(
                [lua, str(HARNESS), cmdline, str(LUA)],
                check=True,
                capture_output=True,
                text=True,
            )
            model = completed.stdout or None
            self.assertEqual(model, expected, cmdline)

    def test_jis_backslash_preserves_other_options_and_owner_choices(self) -> None:
        lua = shutil.which("lua") or shutil.which("lua5.4") or shutil.which("luajit")
        if lua is None:
            self.skipTest("lua required")
        for geometry, layout, variant, options, keymap, expected in (
            ("jis", "jp", "", "", "", "apple:jp_oadg109a"),
            ("jis", "jp", "", "compose:caps", "", "compose:caps,apple:jp_oadg109a"),
            ("jis", "jp", "", "apple:jp_oadg109a", "", "<preserved>"),
            ("jis", "jp", "", "apple:jp_pc106", "", "<preserved>"),
            ("jis", "us", "", "", "", "<preserved>"),
            ("jis", "jp,us", "", "", "", "<preserved>"),
            ("jis", "jp", "kana", "", "", "<preserved>"),
            ("jis", "jp", "", "", "/custom.xkb", "<preserved>"),
            ("ansi", "jp", "", "", "", "<preserved>"),
        ):
            result = subprocess.run(
                [lua, str(HARNESS), "tryomarchy.keyboard=" + geometry, str(LUA), layout, variant, options, keymap],
                check=True, capture_output=True, text=True,
            )
            self.assertEqual(result.stdout, "applealu_" + geometry + "|" + expected)


if __name__ == "__main__":
    unittest.main()
