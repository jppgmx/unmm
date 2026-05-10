import importlib.util
import io
import tempfile
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path
import unittest
import unittest.mock


ROOT = Path(__file__).resolve().parents[1]
MODULE_PATH = ROOT / "assets" / "confldr.py"


def load_confldr():
    spec = importlib.util.spec_from_file_location("confldr", MODULE_PATH)
    module = importlib.util.module_from_spec(spec)
    assert spec is not None and spec.loader is not None
    spec.loader.exec_module(module)
    return module


class ConfldrTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.confldr = load_confldr()

    def write_config(self, directory, name, content):
        path = Path(directory) / name
        path.write_text(content, encoding="utf-8")
        return str(path)

    def run_main(self, argv):
        args = self.confldr.build_parser().parse_args(argv)
        stdout = io.StringIO()
        stderr = io.StringIO()
        with redirect_stdout(stdout), redirect_stderr(stderr):
            code = self.confldr.main(args)
        return code, stdout.getvalue(), stderr.getvalue()

    def run_main_with_stdin(self, argv, stdin_content):
        """
        Executa main() com stdin injetado como string em vez de arquivo.
        """
        args = self.confldr.build_parser().parse_args(argv)
        stdout = io.StringIO()
        stderr = io.StringIO()
        stdin = io.StringIO(stdin_content)
        with redirect_stdout(stdout), redirect_stderr(stderr), \
             unittest.mock.patch('sys.stdin', stdin):
            code = self.confldr.main(args)
        return code, stdout.getvalue(), stderr.getvalue()

    def test_parser_accepts_one_or_more_config_files(self):
        args = self.confldr.build_parser().parse_args(["one.ini", "two.ini"])
        self.assertEqual(args.config_file, ["one.ini", "two.ini"])

    def test_normalize_option_handles_nested_sections(self):
        self.assertEqual(
            self.confldr.normalize_option("Export.OVA.Name"),
            "EXPORT_OVA_NAME",
        )

    def test_normalize_value_handles_lists_and_quotes(self):
        self.assertEqual(
            self.confldr.normalize_value('alpha "beta gamma" delta'),
            ["alpha", "beta gamma", "delta"],
        )

    def test_normalize_value_empty_list_marker(self):
        self.assertEqual(self.confldr.normalize_value("_"), [])

    def test_main_reads_single_config_file(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            config = self.write_config(
                tmpdir,
                "unmm.conf",
                """[General]\nNoLogo=true\nOutputDir=/tmp/out\n\n[Lib.Logging]\nVerbose=true\n\n[System]\nHostname=testbox\n""",
            )
            code, stdout, stderr = self.run_main([config])

        self.assertEqual(code, 0)
        self.assertEqual(stderr, "")
        lines = set(stdout.strip().splitlines())
        self.assertIn("export UNMM_GENERAL_NO_LOGO=true", lines)
        self.assertIn("export UNMM_GENERAL_OUTPUT_DIR=/tmp/out", lines)
        self.assertIn("export UNMM_LIB_LOGGING_VERBOSE=true", lines)
        self.assertIn("export UNMM_SYSTEM_HOSTNAME=testbox", lines)

    def test_main_merges_later_config_files(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            base = self.write_config(
                tmpdir,
                "base.ini",
                """[System]\nHostname=basebox\n""",
            )
            override = self.write_config(
                tmpdir,
                "override.ini",
                """[System]\nHostname=finalbox\n""",
            )
            code, stdout, stderr = self.run_main([base, override])

        self.assertEqual(code, 0)
        self.assertEqual(stderr, "")
        self.assertEqual(stdout.strip(), "export UNMM_SYSTEM_HOSTNAME=finalbox")

    def test_main_set_appends_to_existing_list(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            config = self.write_config(
                tmpdir,
                "list.ini",
                """[List]\nItems=alpha beta\n""",
            )
            code, stdout, stderr = self.run_main([config, "-s", "List.Items+=gamma delta"])

        self.assertEqual(code, 0)
        self.assertEqual(stderr, "")
        self.assertIn("declare -a UNMM_LIST_ITEMS=(alpha beta gamma delta)", stdout.strip().splitlines())

    def test_main_set_creates_list_when_missing(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            config = self.write_config(
                tmpdir,
                "base.ini",
                """[General]\nNoLogo=false\n""",
            )
            code, stdout, stderr = self.run_main([config, "-s", "System.Tags+=one two"])

        self.assertEqual(code, 0)
        self.assertEqual(stderr, "")
        self.assertIn("declare -a UNMM_SYSTEM_TAGS=(one two)", stdout.strip().splitlines())

    def test_main_set_append_to_scalar_returns_clean_error(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            config = self.write_config(
                tmpdir,
                "scalar.ini",
                """[System]\nHostname=basebox\n""",
            )
            code, stdout, stderr = self.run_main([config, "-s", "System.Hostname+=extra"])

        self.assertEqual(code, 1)
        self.assertEqual(stdout, "")
        self.assertIn("não é uma lista", stderr)

    def test_main_emits_lib_logging_variable(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            config = self.write_config(
                tmpdir,
                "liblogging.ini",
                """[Lib.Logging]\nVerbose=false\n""",
            )
            code, stdout, stderr = self.run_main([config, "-s", "Lib.Logging.Verbose=true"])

        self.assertEqual(code, 0)
        self.assertEqual(stderr, "")
        self.assertEqual(stdout.strip(), "export UNMM_LIB_LOGGING_VERBOSE=true")

    def test_main_reads_from_stdin(self):
        """stdin simples: '-' lê config do stdin."""
        ini_content = "[General]\nNoLogo=true\n[System]\nHostname=stdin-box\n"
        code, stdout, stderr = self.run_main_with_stdin(["-"], ini_content)

        self.assertEqual(code, 0)
        self.assertEqual(stderr, "")
        lines = set(stdout.strip().splitlines())
        self.assertIn("export UNMM_GENERAL_NO_LOGO=true", lines)
        self.assertIn("export UNMM_SYSTEM_HOSTNAME=stdin-box", lines)

    def test_main_merges_file_and_stdin(self):
        """arquivo + stdin: primeiro arquivo, depois stdin override."""
        with tempfile.TemporaryDirectory() as tmpdir:
            base = self.write_config(
                tmpdir,
                "base.ini",
                "[General]\nNoLogo=false\nMountPoint=/mnt/base\n",
            )
            stdin_override = "[General]\nNoLogo=true\n"
            code, stdout, stderr = self.run_main_with_stdin([base, "-"], stdin_override)

        self.assertEqual(code, 0)
        self.assertEqual(stderr, "")
        lines = set(stdout.strip().splitlines())
        self.assertIn("export UNMM_GENERAL_NO_LOGO=true", lines)  # stdin override
        self.assertIn("export UNMM_GENERAL_MOUNT_POINT=/mnt/base", lines)  # from base

    def test_main_multiple_stdin_uses_same_buffer(self):
        """múltiplos '-': reutiliza mesmo stdin (buffer)."""
        ini_content = "[General]\nNoLogo=true\n"
        code, stdout, stderr = self.run_main_with_stdin(["-", "-"], ini_content)

        self.assertEqual(code, 0)
        self.assertEqual(stderr, "")
        # Ambos "-" devem ler o mesmo stdin (uma única vez)
        lines = stdout.strip().splitlines()
        # NoLogo deve aparecer uma vez (não duplicado)
        count = sum(1 for line in lines if "UNMM_GENERAL_NO_LOGO=true" in line)
        self.assertEqual(count, 1)

    def test_main_stdin_with_set_override(self):
        """stdin + --set: stdin mais overrides via CLI."""
        ini_content = "[General]\nNoLogo=true\n\n[Lib.Logging]\nVerbose=false\n"
        code, stdout, stderr = self.run_main_with_stdin(
            ["-", "-s", "Lib.Logging.Verbose=true"],
            ini_content
        )

        self.assertEqual(code, 0)
        self.assertEqual(stderr, "")
        lines = set(stdout.strip().splitlines())
        self.assertIn("export UNMM_GENERAL_NO_LOGO=true", lines)  # from stdin
        self.assertIn("export UNMM_LIB_LOGGING_VERBOSE=true", lines)  # overridden by --set

    def test_main_stdin_invalid_ini_returns_error(self):
        """stdin com INI inválido: retorna erro."""
        invalid_ini = "[Section\n"  # missing ']'
        code, stdout, stderr = self.run_main_with_stdin(["-"], invalid_ini)

        self.assertEqual(code, 1)
        self.assertIn("Erro ao carregar configuração", stderr)
        self.assertEqual(stdout, "")


if __name__ == "__main__":
    unittest.main()