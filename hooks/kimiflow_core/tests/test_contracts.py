import io
import unittest

from kimiflow_core import contracts


class TestContracts(unittest.TestCase):
    def test_compact_json_has_no_spaces(self):
        self.assertEqual(contracts.dumps({"a": 1, "b": [True, None]}), '{"a":1,"b":[true,null]}')

    def test_pretty_json_uses_two_space_indent(self):
        self.assertEqual(contracts.dumps({"a": 1}, pretty=True), '{\n  "a": 1\n}')

    def test_json_print_adds_trailing_newline(self):
        out = io.StringIO()
        contracts.json_print({"a": 1}, stream=out)
        self.assertEqual(out.getvalue(), '{"a":1}\n')


if __name__ == "__main__":
    unittest.main()
