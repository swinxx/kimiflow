import os
import shutil
import tempfile
import unittest

from kimiflow_core import state


class TestState(unittest.TestCase):
    def test_state_value_is_case_insensitive_and_markdown_tolerant(self):
        text = "- **Scope:** Small\nMode: feature\n"
        self.assertEqual(state.state_value_text(text, "scope"), "Small")
        self.assertEqual(state.state_value_text(text, "MODE"), "feature")

    def test_first_matching_key_wins(self):
        text = "Scope: small\nscope: large\n"
        self.assertEqual(state.state_value_text(text, "scope"), "small")

    def test_missing_key_returns_empty_string(self):
        self.assertEqual(state.state_value_text("Mode: feature\n", "scope"), "")

    def test_state_value_reads_file(self):
        d = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, d)
        p = os.path.join(d, "STATE.md")
        with open(p, "w", encoding="utf-8") as handle:
            handle.write("Alias: quick\n")
        self.assertEqual(state.state_value(p, "alias"), "quick")


if __name__ == "__main__":
    unittest.main()
