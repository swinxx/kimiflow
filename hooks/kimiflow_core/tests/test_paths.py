import os
import shutil
import subprocess
import tempfile
import unittest

from kimiflow_core import paths


class TestPaths(unittest.TestCase):
    def setUp(self):
        self.d = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.d)

    def test_explicit_root_strict_resolves_existing_directory(self):
        self.assertEqual(paths.resolve_root(self.d, cwd="/"), self.d)

    def test_explicit_root_strict_rejects_missing_directory(self):
        with self.assertRaises(paths.RootResolutionError):
            paths.resolve_root(os.path.join(self.d, "missing"), cwd="/", mode="strict")

    def test_explicit_root_observational_preserves_missing_directory(self):
        missing = os.path.join(self.d, "missing")
        self.assertEqual(paths.resolve_root(missing, cwd="/", mode="observational"), missing)

    def test_hook_safe_returns_none_for_missing_cwd(self):
        missing = os.path.join(self.d, "missing")
        self.assertIsNone(paths.resolve_root(cwd=missing, mode="hook_safe"))

    def test_implicit_root_prefers_git_toplevel(self):
        repo = os.path.join(self.d, "repo")
        nested = os.path.join(repo, "a", "b")
        os.makedirs(nested)
        subprocess.run(["git", "init", "-q", repo], check=True)
        self.assertEqual(paths.resolve_root(cwd=nested), os.path.realpath(repo))

    def test_rel_path_inside_root(self):
        self.assertEqual(paths.rel_path("/tmp/repo", "/tmp/repo/hooks/a.sh"), "hooks/a.sh")

    def test_rel_path_outside_root_stays_absolute(self):
        self.assertEqual(paths.rel_path("/tmp/repo", "/tmp/other/a.sh"), "/tmp/other/a.sh")


if __name__ == "__main__":
    unittest.main()
