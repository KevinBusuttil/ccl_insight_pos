import importlib.util
import sys
import unittest
from pathlib import Path


MODULE_PATH = (
    Path(__file__).parents[2] / "tool" / "server_e2e" / "adb_ui.py"
)
SPEC = importlib.util.spec_from_file_location("adb_ui", MODULE_PATH)
assert SPEC and SPEC.loader
ADB_UI = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = ADB_UI
SPEC.loader.exec_module(ADB_UI)


class UiNodeTest(unittest.TestCase):
    def test_bounds_and_center_are_parsed(self) -> None:
        node = ADB_UI.UiNode({"bounds": "[10,20][110,220]"})

        self.assertEqual(node.bounds, (10, 20, 110, 220))
        self.assertEqual(node.center, (60, 120))

    def test_invalid_bounds_are_rejected(self) -> None:
        node = ADB_UI.UiNode({"bounds": "missing"})

        with self.assertRaises(RuntimeError):
            _ = node.bounds

    def test_text_encoding_preserves_spaces_for_android_input(self) -> None:
        self.assertEqual(
            ADB_UI.encode_adb_text("Shop A 100%"),
            "Shop%sA%s100%25",
        )

    def test_merged_autocomplete_node_taps_editable_region(self) -> None:
        node = ADB_UI.UiNode(
            {
                "bounds": "[100,900][900,1800]",
                "hint": "Customer\nC-001 Customer One\nC-002 Customer Two",
            }
        )

        self.assertEqual(ADB_UI.text_field_tap_position(node), (500, 1080))

    def test_wide_merged_node_taps_field_near_top(self) -> None:
        node = ADB_UI.UiNode(
            {
                "bounds": "[1756,648][2476,1196]",
                "hint": "Sale Composer\nCustomer\nSelected: C-001",
            }
        )

        self.assertEqual(ADB_UI.text_field_tap_position(node), (2116, 780))
        self.assertEqual(ADB_UI.suffix_icon_tap_position(node), (2428, 780))


if __name__ == "__main__":
    unittest.main()
