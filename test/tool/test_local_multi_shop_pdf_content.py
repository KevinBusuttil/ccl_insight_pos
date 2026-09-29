import importlib.util
import sys
import unittest
from pathlib import Path


MODULE_PATH = (
    Path(__file__).parents[2]
    / "tool"
    / "docs"
    / "generate_local_multi_shop_pdfs.py"
)
SPEC = importlib.util.spec_from_file_location(
    "generate_local_multi_shop_pdfs", MODULE_PATH
)
assert SPEC and SPEC.loader
PDFS = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = PDFS
SPEC.loader.exec_module(PDFS)


class LocalMultiShopPdfContentTest(unittest.TestCase):
    def test_guide_cover_uses_compact_square_monogram(self) -> None:
        self.assertEqual(PDFS.GUIDE_COVER_MARK_WIDTH, 118)
        self.assertEqual(
            PDFS.GUIDE_COVER_MARK_HEIGHT,
            PDFS.GUIDE_COVER_MARK_WIDTH,
        )
        self.assertLess(PDFS.GUIDE_COVER_MARK_HEIGHT, PDFS.PAGE_H * 0.25)

    def test_output_names_are_stable(self) -> None:
        self.assertEqual(
            PDFS.OUTPUT / "Neuradix_POS_Local_Multi_Shop_User_Guide.pdf",
            PDFS.ROOT
            / "output"
            / "pdf"
            / "Neuradix_POS_Local_Multi_Shop_User_Guide.pdf",
        )

    def test_required_source_documents_exist(self) -> None:
        required = [
            PDFS.ROOT
            / "docs"
            / "guides"
            / "neuradix_pos_local_multi_shop_user_guide.md",
            PDFS.ROOT
            / "docs"
            / "architecture"
            / "neuradix_pos_technical_architecture.md",
            PDFS.RESULT,
            PDFS.AUDIT,
        ]

        self.assertTrue(all(path.exists() for path in required))

    def test_documentation_contains_recovery_and_storage_boundaries(self) -> None:
        guide = (
            PDFS.ROOT
            / "docs"
            / "guides"
            / "neuradix_pos_local_multi_shop_user_guide.md"
        ).read_text()
        architecture = (
            PDFS.ROOT
            / "docs"
            / "architecture"
            / "neuradix_pos_technical_architecture.md"
        ).read_text()

        self.assertIn("If every synchronized device is lost", guide)
        self.assertIn("No Local Multi-Shop Product, Customer, Sale", architecture)
        self.assertIn("ERPNext is one supported connector", architecture)


if __name__ == "__main__":
    unittest.main()
