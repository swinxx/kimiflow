import unittest

from memory_router import clock


class DateDaysAgoCase(unittest.TestCase):
    def test_zero_is_today(self):
        self.assertEqual(clock.date_days_ago(0), clock.date_now())

    def test_string_digits_match_int(self):
        self.assertEqual(clock.date_days_ago("90"), clock.date_days_ago(90))

    def test_offset_is_earlier_and_well_formed(self):
        older = clock.date_days_ago(10)
        self.assertLess(older, clock.date_days_ago(0))
        self.assertRegex(older, r"^\d{4}-\d{2}-\d{2}$")

    def test_non_numeric_returns_empty(self):
        # Bash prints '' when neither `date` form accepts the argument.
        self.assertEqual(clock.date_days_ago("abc"), "")


if __name__ == "__main__":
    unittest.main()
