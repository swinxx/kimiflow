import os
import unittest
from unittest import mock

from memory_router import global_metrics


class EnabledCase(unittest.TestCase):
    def enabled(self, value):
        with mock.patch.dict(os.environ, {"KIMIFLOW_GLOBAL_METRICS": value}):
            return global_metrics.enabled()

    def test_disabled_spellings(self):
        for off in ("off", "OFF", "0", "false", "FALSE", "no", "NO"):
            self.assertFalse(self.enabled(off), off)

    def test_enabled_spellings(self):
        for on in ("on", "ON", "1", "yes", "true", "whatever", ""):
            self.assertTrue(self.enabled(on), on)

    def test_default_when_unset(self):
        with mock.patch.dict(os.environ, {}, clear=True):
            self.assertTrue(global_metrics.enabled())


class BaseDirCase(unittest.TestCase):
    def test_kimiflow_home_wins(self):
        with mock.patch.dict(os.environ, {"KIMIFLOW_HOME": "/k", "HOME": "/h"}):
            self.assertEqual(global_metrics.base_dir(), "/k/metrics")

    def test_falls_back_to_home(self):
        env = {"HOME": "/h"}
        with mock.patch.dict(os.environ, env, clear=True):
            self.assertEqual(global_metrics.base_dir(), "/h/.kimiflow/metrics")

    def test_empty_kimiflow_home_falls_back_to_home(self):
        with mock.patch.dict(os.environ, {"KIMIFLOW_HOME": "", "HOME": "/h"}):
            self.assertEqual(global_metrics.base_dir(), "/h/.kimiflow/metrics")

    def test_none_without_any_home(self):
        with mock.patch.dict(os.environ, {}, clear=True):
            self.assertIsNone(global_metrics.base_dir())

    def test_none_when_base_is_root(self):
        with mock.patch.dict(os.environ, {"KIMIFLOW_HOME": "/"}):
            self.assertIsNone(global_metrics.base_dir())


class DisplayPathCase(unittest.TestCase):
    def test_fixed_path(self):
        self.assertEqual(global_metrics.display_path(), "~/.kimiflow/metrics/token-economics.jsonl")


if __name__ == "__main__":
    unittest.main()
