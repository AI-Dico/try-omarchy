"""Japanese first-session defaults and preservation of personal IME settings."""
import importlib.machinery
import importlib.util
import configparser
from pathlib import Path
import tempfile
import unittest

GUEST = Path(__file__).resolve().parents[1]
SCRIPT = GUEST / "native-overlay/usr/local/bin/try-omarchy-input-init"
loader = importlib.machinery.SourceFileLoader("input_init", str(SCRIPT))
spec = importlib.util.spec_from_loader(loader.name, loader)
module = importlib.util.module_from_spec(spec)
loader.exec_module(module)


class JapaneseInputTests(unittest.TestCase):
    def test_initial_japanese_profiles_and_non_japanese_preservation(self):
        factory = GUEST / "fragments/fcitx5-profile.ini"
        original = factory.read_text()
        for cmdline, lang, layout in (
            ("tryomarchy.keyboard=jis", "en_US.UTF-8", "jp"),
            ("tryomarchy.keyboard=ansi", "ja_JP.UTF-8", "us"),
            ("tryomarchy.keyboard=iso", "ja_JP.UTF-8", "us"),
            ("xtryomarchy.keyboard=jis", "en_US.UTF-8", None),
            ("tryomarchy.keyboard=jisextra", "zh_TW.UTF-8", None),
            ("tryomarchy.keyboard=iso", "zh_TW.UTF-8", None),
        ):
            with self.subTest(cmdline=cmdline, lang=lang), tempfile.TemporaryDirectory() as tmp:
                profile = Path(tmp) / "profile"
                profile.write_text(original)
                module.initialize(profile, factory, cmdline, lang, layout or "us")
                updated = profile.read_text()
                self.assertEqual(updated.partition("[Groups/1]")[2], original.partition("[Groups/1]")[2])
                if layout:
                    self.assertIn(f"Default Layout={layout}\n", updated)
                    self.assertIn(f"[Groups/0/Items/0]\nName=keyboard-{layout}\n", updated)
                    self.assertIn("[Groups/0/Items/1]\nName=mozc\n", updated)
                    self.assertIn("[Groups/0/Items/2]\nName=chewing\n", updated)
                    self.assertIn("DefaultIM=mozc\n", updated)
                else:
                    self.assertEqual(updated, original)
                config = profile.parent / "config"
                if cmdline == "tryomarchy.keyboard=jis":
                    keys = configparser.ConfigParser()
                    keys.read(config)
                    self.assertEqual(keys["Hotkey/ActivateKeys"]["0"], "Hangul")
                    self.assertEqual(keys["Hotkey/DeactivateKeys"]["0"], "Hangul_Hanja")
                    self.assertTrue(keys["Hotkey"].getboolean("ConsumeRedundantActivateKeys"))
                    self.assertNotIn("Hangul", keys["Hotkey/TriggerKeys"].values())
                else:
                    self.assertFalse(config.exists())
                module.initialize(profile, factory, cmdline, lang)
                self.assertEqual(profile.read_text(), updated)

    def test_preserves_korean_first_group_on_jis(self):
        factory = GUEST / "fragments/fcitx5-profile.ini"
        korean = factory.read_text().replace("0=Default\n1=Korean\n", "0=Korean\n1=Default\n")
        with tempfile.TemporaryDirectory() as tmp:
            profile = Path(tmp) / "profile"
            profile.write_text(korean)
            module.initialize(profile, factory, "tryomarchy.keyboard=jis", "ko_KR.UTF-8", "jp")
            self.assertEqual(profile.read_text(), korean)
            self.assertFalse((profile.parent / "config").exists())

    def test_preserves_custom_profiles_missing_profiles_and_symlinks(self):
        factory = GUEST / "fragments/fcitx5-profile.ini"
        with tempfile.TemporaryDirectory() as tmp:
            profile = Path(tmp) / "profile"
            module.initialize(profile, factory, "tryomarchy.keyboard=jis", "ja_JP.UTF-8")
            self.assertFalse(profile.exists())
            profile.write_text("# My custom engine and shortcuts\n")
            module.initialize(profile, factory, "tryomarchy.keyboard=jis", "ja_JP.UTF-8")
            self.assertEqual(profile.read_text(), "# My custom engine and shortcuts\n")
            target = Path(tmp) / "target"
            target.write_bytes(factory.read_bytes())
            profile.unlink()
            profile.symlink_to(target)
            module.initialize(profile, factory, "tryomarchy.keyboard=jis", "ja_JP.UTF-8")
            self.assertEqual(target.read_bytes(), factory.read_bytes())

    def test_preserves_personal_hotkeys_and_explicit_us_layout_on_jis(self):
        factory = GUEST / "fragments/fcitx5-profile.ini"
        with tempfile.TemporaryDirectory() as tmp:
            profile = Path(tmp) / "profile"
            profile.write_bytes(factory.read_bytes())
            config = Path(tmp) / "config"
            config.write_text("# Personal hotkeys\n")
            module.initialize(profile, factory, "tryomarchy.keyboard=jis", "en_US.UTF-8", "us")
            self.assertEqual(config.read_text(), "# Personal hotkeys\n")
            self.assertIn("Name=keyboard-us", profile.read_text())
