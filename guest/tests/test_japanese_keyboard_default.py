"""Exercise the reviewed setup prompt with simulated host geometries."""
from pathlib import Path
import os
import subprocess
import tempfile
import unittest

GUEST = Path(__file__).resolve().parents[1]


class JapaneseKeyboardDefaultTests(unittest.TestCase):
    def test_only_jis_preselects_japanese_and_an_explicit_choice_wins(self):
        source = GUEST / "tests/fixtures/japanese-keyboard-setup.sh"
        with tempfile.TemporaryDirectory() as tmp:
            form = Path(tmp) / "setup-form.sh"
            form.write_bytes(source.read_bytes())
            for patch in ("keyboard-us-acentos.patch",):
                subprocess.run(["patch", str(form), str(GUEST / "patches/omarchy" / patch)], check=True, capture_output=True)
            script = r'''
source "$1"
cat() { if [[ $1 == /proc/cmdline ]]; then printf "root=/dev/vda tryomarchy.keyboard=%s" "$GEOMETRY"; else command cat "$@"; fi; }
gum() {
  while (($#)); do
    if [[ $1 == --selected ]]; then selected=$2; break; fi
    shift
  done
  printf '%s' "${CHOICE:-$selected}"
}
omarchy_prompt_keyboard
printf '%s|%s' "$keyboard_label" "$keyboard"
'''
            for geometry, choice, expected in (
                ("jis", "", "Japanese|jp106"),
                ("ansi", "", "English (US)|us"),
                ("iso", "", "English (US)|us"),
                ("jis-extra", "", "English (US)|us"),
                ("jis", "English (US)", "English (US)|us"),
            ):
                result = subprocess.run(["bash", "-c", script, "bash", str(form)], env={**os.environ, "GEOMETRY": geometry, "CHOICE": choice}, check=True, capture_output=True, text=True)
                self.assertEqual(result.stdout, expected)
