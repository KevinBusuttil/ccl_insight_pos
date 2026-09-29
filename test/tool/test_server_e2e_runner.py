import importlib.util
import sys
import unittest
from pathlib import Path


TOOL_ROOT = Path(__file__).parents[2] / "tool" / "server_e2e"
sys.path.insert(0, str(TOOL_ROOT))
MODULE_PATH = TOOL_ROOT / "local_multi_shop_server_e2e.py"
SPEC = importlib.util.spec_from_file_location("local_multi_shop_server_e2e", MODULE_PATH)
assert SPEC and SPEC.loader
RUNNER = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = RUNNER
SPEC.loader.exec_module(RUNNER)


class ServerE2ERunnerTest(unittest.TestCase):
    def test_detects_resumed_pos_activity(self) -> None:
        state = (
            "mResumedActivity: ActivityRecord{abc u0 "
            "com.busuttiltechnologies.neuradix_pos/.MainActivity t12}"
        )

        self.assertTrue(
            RUNNER.package_is_resumed(state, RUNNER.PACKAGE),
        )

    def test_rejects_launcher_as_foreground(self) -> None:
        state = (
            "mResumedActivity: ActivityRecord{abc u0 "
            "com.google.android.apps.nexuslauncher/.NexusLauncherActivity t1}"
        )

        self.assertFalse(
            RUNNER.package_is_resumed(state, RUNNER.PACKAGE),
        )

    def test_detects_only_fully_visible_input_method(self) -> None:
        self.assertTrue(
            RUNNER.input_method_is_shown(
                "mImeWindowVis=3\n  mInputShown=true\n  mWindowVisible=true"
            )
        )
        self.assertFalse(
            RUNNER.input_method_is_shown(
                "mImeWindowVis=0\n  mInputShown=false\n  mWindowVisible=false"
            )
        )

    def test_certification_result_rejects_stale_pending_snapshot(self) -> None:
        passing = RUNNER.RegisterState(
            business_id="NBIZ-1",
            shop_id="SHOP-A",
            shop_name="Shop A",
            device_id="DEVICE-A",
            item_count=4,
            customer_count=6,
            sale_count=18,
            outgoing_sale_count=9,
            pending_count=0,
        )
        stale = RUNNER.RegisterState(
            business_id="NBIZ-1",
            shop_id="SHOP-B",
            shop_name="Shop B",
            device_id="DEVICE-B",
            item_count=4,
            customer_count=6,
            sale_count=18,
            outgoing_sale_count=9,
            pending_count=1,
        )

        with self.assertRaisesRegex(AssertionError, "inconsistent certification"):
            RUNNER.build_certification_result(
                run_id="run",
                timestamp_utc="2026-09-29T00:00:00Z",
                a=passing,
                b=stale,
            )

    def test_certification_result_contains_verified_states(self) -> None:
        state_a = RUNNER.RegisterState(
            "NBIZ-1", "SHOP-A", "Shop A", "DEVICE-A", 4, 6, 18, 9, 0
        )
        state_b = RUNNER.RegisterState(
            "NBIZ-1", "SHOP-B", "Shop B", "DEVICE-B", 4, 6, 18, 9, 0
        )

        result = RUNNER.build_certification_result(
            run_id="run",
            timestamp_utc="2026-09-29T00:00:00Z",
            a=state_a,
            b=state_b,
        )

        self.assertEqual(result["business_id"], "NBIZ-1")
        self.assertEqual(result["shop_a"]["pending_count"], 0)
        self.assertEqual(result["shop_b"]["sale_count"], 18)

    def test_completed_mixed_stage_is_resumable(self) -> None:
        complete_a = RUNNER.RegisterState(
            "NBIZ-1", "SHOP-A", "Shop A", "DEVICE-A", 4, 6, 18, 9, 0
        )
        complete_b = RUNNER.RegisterState(
            "NBIZ-1", "SHOP-B", "Shop B", "DEVICE-B", 4, 6, 18, 9, 0
        )
        incomplete = RUNNER.RegisterState(
            "NBIZ-1", "SHOP-B", "Shop B", "DEVICE-B", 4, 6, 17, 9, 1
        )

        self.assertTrue(RUNNER.mixed_mode_is_complete(complete_a, complete_b))
        self.assertFalse(RUNNER.mixed_mode_is_complete(complete_a, incomplete))


if __name__ == "__main__":
    unittest.main()
