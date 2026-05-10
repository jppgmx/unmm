import importlib.util
import io
import unittest
from contextlib import redirect_stdout, redirect_stderr
from decimal import Decimal
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MODULE_PATH = ROOT / "assets" / "unicalc.py"


def load_unit_module():
    spec = importlib.util.spec_from_file_location("unit", MODULE_PATH)
    module = importlib.util.module_from_spec(spec)
    assert spec is not None and spec.loader is not None
    spec.loader.exec_module(module)
    return module


class UnitTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.unit = load_unit_module()

    def run_main(self, argv):
        args = self.unit.build_parser().parse_args(argv)
        stdout = io.StringIO()
        stderr = io.StringIO()
        with redirect_stdout(stdout), redirect_stderr(stderr):
            code = self.unit.main(args)
        return code, stdout.getvalue(), stderr.getvalue()

    def test_parse_unittype_normalizes_bit_and_byte(self):
        self.assertEqual(self.unit.parse_unittype("kb"), self.unit.UnitType.KILOBIT)
        self.assertEqual(self.unit.parse_unittype("KB"), self.unit.UnitType.KILOBYTE)
        self.assertEqual(self.unit.parse_unittype("kib"), self.unit.UnitType.KIBIBIT)
        self.assertEqual(self.unit.parse_unittype("KiB"), self.unit.UnitType.KIBIBYTE)

    def test_unit_to_converts_between_si_units(self):
        value = self.unit.Unit("1MB").to("KB")
        self.assertEqual(value.value, Decimal("1000"))
        self.assertEqual(value.unit_type, self.unit.UnitType.KILOBYTE)

    def test_unit_to_converts_between_iec_units(self):
        value = self.unit.Unit("1MiB").to("B")
        self.assertEqual(value.value, Decimal("1048576"))
        self.assertEqual(value.unit_type, self.unit.UnitType.BYTE)

    def test_unit_to_converts_bits_to_bytes(self):
        value = self.unit.Unit("8b").to("B")
        self.assertEqual(value.value, Decimal("1"))
        self.assertEqual(value.unit_type, self.unit.UnitType.BYTE)

    def test_unit_add_and_subtract(self):
        result = self.unit.Unit("1MB") + self.unit.Unit("500KB")
        self.assertEqual(result.unit_type, self.unit.UnitType.MEGABYTE)
        self.assertEqual(result.value, Decimal("1.5"))

        result = self.unit.Unit("2MB") - self.unit.Unit("500KB")
        self.assertEqual(result.unit_type, self.unit.UnitType.MEGABYTE)
        self.assertEqual(result.value, Decimal("1.5"))

    def test_unit_multiply_and_divide(self):
        result = self.unit.Unit("2MB") * 2
        self.assertEqual(result.value, Decimal("4"))
        self.assertEqual(result.unit_type, self.unit.UnitType.MEGABYTE)

        result = self.unit.Unit("2MB") / 4
        self.assertEqual(result.value, Decimal("0.5"))
        self.assertEqual(result.unit_type, self.unit.UnitType.MEGABYTE)

    def test_unit_comparisons(self):
        self.assertTrue(self.unit.Unit("1MB") > self.unit.Unit("900KB"))
        self.assertTrue(self.unit.Unit("8b") == self.unit.Unit("1B"))
        self.assertTrue(self.unit.Unit("1MiB") >= self.unit.Unit("1024KiB"))
        self.assertTrue(self.unit.Unit("1MB") != self.unit.Unit("1MiB"))

    def test_unit_invalid_parse_raises(self):
        with self.assertRaises(ValueError):
            self.unit.Unit("10XB")

    def test_cli_convert(self):
        code, stdout, stderr = self.run_main(["convert", "1MB", "KB", "1"])
        self.assertEqual(code, 0)
        self.assertEqual(stderr, "")
        self.assertEqual(stdout.strip(), "1000KB")

    def test_cli_compare(self):
        code, stdout, stderr = self.run_main(["compare", "1MB", "1000KB", "eq"])
        self.assertEqual(code, 0)
        self.assertEqual(stderr, "")
        self.assertEqual(stdout, "")

        code, stdout, stderr = self.run_main(["compare", "1MB", "1MiB", "eq"])
        self.assertEqual(code, 1)
        self.assertEqual(stderr, "")
        self.assertEqual(stdout, "")


if __name__ == "__main__":
    unittest.main()
