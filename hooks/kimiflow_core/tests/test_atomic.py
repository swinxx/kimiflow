import os
import shutil
import stat
import tempfile
import unittest

from kimiflow_core import atomic


class TestAtomic(unittest.TestCase):
    def setUp(self):
        self.d = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.d)

    def test_atomic_write_creates_0600_file_by_default(self):
        path = os.path.join(self.d, "INDEX.json")
        atomic.atomic_write(path, "{}\n")
        with open(path, encoding="utf-8") as handle:
            self.assertEqual(handle.read(), "{}\n")
        mode = stat.S_IMODE(os.stat(path).st_mode)
        self.assertEqual(mode, 0o600)

    def test_atomic_write_leaves_no_temp_sibling(self):
        path = os.path.join(self.d, "out.txt")
        atomic.atomic_write(path, "x")
        self.assertEqual(os.listdir(self.d), ["out.txt"])

    def test_atomic_write_refuses_symlink(self):
        real = os.path.join(self.d, "real.txt")
        link = os.path.join(self.d, "link.txt")
        atomic.atomic_write(real, "safe")
        os.symlink(real, link)
        with self.assertRaises(ValueError):
            atomic.atomic_write(link, "unsafe")
        with open(real, encoding="utf-8") as handle:
            self.assertEqual(handle.read(), "safe")


if __name__ == "__main__":
    unittest.main()
