import importlib.util
import sys
import unittest
from pathlib import Path


MODULE_PATH = (
    Path(__file__).parents[2]
    / "tool"
    / "server_e2e"
    / "audit_server_storage.py"
)
SPEC = importlib.util.spec_from_file_location("audit_server_storage", MODULE_PATH)
assert SPEC and SPEC.loader
AUDIT = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = AUDIT
SPEC.loader.exec_module(AUDIT)


class ServerStorageAuditTest(unittest.TestCase):
    def test_builds_scoped_operational_row_query(self) -> None:
        sql = AUDIT.build_audit_sql("NBIZ-00004")

        self.assertIn('business="NBIZ-00004"', sql)
        self.assertIn("`tabNeuradix Sale Item`", sql)

    def test_rejects_unsafe_business_identifier(self) -> None:
        with self.assertRaisesRegex(ValueError, "Unsafe business id"):
            AUDIT.build_audit_sql('NBIZ-1" OR 1=1')

    def test_parses_all_zero_counts(self) -> None:
        output = "\n".join(
            [
                "Neuradix Product\t0",
                "Neuradix Customer\t0",
                "Neuradix Sale\t0",
                "Neuradix Sale Item\t0",
            ]
        )

        counts = AUDIT.parse_audit_output(output)

        self.assertEqual(set(counts), set(AUDIT.EXPECTED_TABLES))
        self.assertTrue(all(count == 0 for count in counts.values()))

    def test_rejects_incomplete_sql_output(self) -> None:
        with self.assertRaisesRegex(ValueError, "omitted tables"):
            AUDIT.parse_audit_output("Neuradix Product\t0")


if __name__ == "__main__":
    unittest.main()
