"""Unit tests for the reply parser, using a real captured reply (no hardware needed).

Run: python -m unittest discover -s linux/tests
"""
import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
import msi_psu  # noqa: E402

# Captured reply to 51 E0 from an Ai1300P; the leading 00 is the report ID.
SAMPLE = bytes.fromhex(
    "0051E001D300F001D30CF001D301F001D30FF001D308F001D320F085CA17E0AEC915E0350890EA1D0000080000000000"
)


class ParseTest(unittest.TestCase):
    def test_sample_reply(self):
        r = msi_psu.parse_read_all(SAMPLE)
        self.assertEqual(r["watts_out"], 106)
        self.assertEqual(r["efficiency"], 82)
        self.assertEqual(r["temp_c"], 29)
        self.assertAlmostEqual(r["v12_total"]["v"], 12.016, places=3)
        self.assertEqual(r["v12_total"]["a"], 8)
        self.assertAlmostEqual(r["v5"]["v"], 5.039, places=3)
        self.assertAlmostEqual(r["v5"]["a"], 1.438, places=3)
        self.assertEqual(len(r["v12_rails"]), 5)
        self.assertAlmostEqual(r["watts_in"], 129.3, places=1)

    def test_without_report_id(self):
        r = msi_psu.parse_read_all(SAMPLE[1:])
        self.assertEqual(r["watts_out"], 106)

    def test_rejected(self):
        with self.assertRaises(ValueError):
            msi_psu.parse_read_all(bytes([0x00, 0x51, 0xFE]) + bytes(61))

    def test_linear11(self):
        self.assertEqual(msi_psu.linear11(0x0C, 0xF0), 3.0)  # 0xF00C: mantissa 12, exponent -2


if __name__ == "__main__":
    unittest.main()
