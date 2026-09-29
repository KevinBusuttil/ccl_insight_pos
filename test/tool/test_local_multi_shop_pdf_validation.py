import importlib.util
import sys
import unittest
from pathlib import Path


MODULE_PATH = (
    Path(__file__).parents[2]
    / "tool"
    / "docs"
    / "validate_local_multi_shop_pdfs.py"
)
SPEC = importlib.util.spec_from_file_location(
    "validate_local_multi_shop_pdfs", MODULE_PATH
)
assert SPEC and SPEC.loader
VALIDATION = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = VALIDATION
SPEC.loader.exec_module(VALIDATION)


class LocalMultiShopPdfValidationTest(unittest.TestCase):
    def test_specs_cover_both_required_deliverables(self) -> None:
        self.assertEqual(
            {spec.path.name for spec in VALIDATION.SPECS},
            {
                "Neuradix_POS_Local_Multi_Shop_User_Guide.pdf",
                "Neuradix_POS_Technical_Architecture.pdf",
            },
        )

    def test_generated_artifacts_pass_validation(self) -> None:
        self.assertEqual(VALIDATION.validate_all(), [])

    def test_validation_rejects_ax_as_a_standalone_term(self) -> None:
        self.assertIsNotNone(VALIDATION.re.search(r"\bAX\b", "Direct AX call"))
        self.assertIsNone(VALIDATION.re.search(r"\bAX\b", "maximum"))


if __name__ == "__main__":
    unittest.main()
