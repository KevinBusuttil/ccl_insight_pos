#!/usr/bin/env python3
"""ADB acceptance runner for an already paired Local Multi-Shop business.

Registration, shop creation, and pairing are deliberately separate from this
data matrix because they require a one-time owner credential supplied through
the UI. This runner fails unless both clean registers are already trusted,
belong to one business, and are assigned to different shops.
"""

from __future__ import annotations

import argparse
import json
import shutil
import sqlite3
import subprocess
import tempfile
import time
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path

from adb_ui import AdbUi, DEFAULT_ADB, UiNode, suffix_icon_tap_position


PACKAGE = "com.busuttiltechnologies.neuradix_pos"
DATABASE = "neuradix_pos.db"


def package_is_resumed(activity_state: str, package: str) -> bool:
    return any(
        "mResumedActivity" in line and package in line
        for line in activity_state.splitlines()
    )


def input_method_is_shown(input_method_state: str) -> bool:
    return (
        "mInputShown=true" in input_method_state
        and "mImeWindowVis=3" in input_method_state
    )


@dataclass(frozen=True)
class RegisterState:
    business_id: str
    shop_id: str
    shop_name: str
    device_id: str
    item_count: int
    customer_count: int
    sale_count: int
    outgoing_sale_count: int
    pending_count: int


class Register:
    def __init__(self, serial: str, label: str, adb: str, output: Path) -> None:
        self.serial = serial
        self.label = label
        self.adb = adb
        self.ui = AdbUi(serial, adb)
        self.output = output

    def shell(self, *args: str, timeout: float = 30) -> str:
        return self.ui.shell(*args, timeout=timeout)

    def set_online(self, online: bool) -> None:
        mode = "disable" if online else "enable"
        self.shell("cmd", "connectivity", "airplane-mode", mode)
        time.sleep(3)

    def force_stop(self) -> None:
        self.shell("am", "force-stop", PACKAGE)
        time.sleep(1)

    def launch(self) -> None:
        if not self._is_foreground():
            self.shell(
                "monkey",
                "-p",
                PACKAGE,
                "-c",
                "android.intent.category.LAUNCHER",
                "1",
            )
        self.ui.wait("content-desc", "Mode: Local Multi-Shop", exact=False, timeout=60)

    def restart(self) -> None:
        self.force_stop()
        self.launch()

    def screenshot(self, name: str) -> Path:
        destination = self.output / f"{name}_{self.label}.png"
        self.ui.screenshot(destination)
        return destination

    def navigate(self, label: str) -> None:
        self.launch()
        for _ in range(3):
            try:
                self.ui.tap("content-desc", label)
                time.sleep(1)
                return
            except RuntimeError:
                self.ui.swipe(100, 760, 960, 760, 500)
                time.sleep(1)
        raise RuntimeError(f"Cannot reveal {label!r} navigation on {self.serial}")

    def create_item(
        self,
        *,
        sku: str,
        barcode: str,
        name: str,
        price: str,
        stock: str,
    ) -> None:
        self.navigate("Inventory")
        self.ui.tap("content-desc", "Add Item")
        self.ui.replace_text("SKU", sku)
        self.ui.replace_text("Barcode", barcode)
        self.ui.replace_text("Name", name)
        self.ui.replace_text("Price", price)
        self.ui.replace_text("Stock Qty", stock)
        self.ui.keyevent("4")
        time.sleep(0.5)
        self.ui.tap("content-desc", "Save")
        self._wait_for_local_value(
            lambda: sku in self.inventory_skus(),
            f"inventory item {sku}",
        )

    def create_customer(
        self,
        *,
        code: str,
        name: str,
        mobile: str,
        email: str,
        address: str,
    ) -> None:
        self.navigate("Customers")
        self.ui.tap("content-desc", "Add Customer")
        self.ui.replace_text("Customer Code", code)
        self.ui.replace_text("Customer Name", name)
        self.ui.replace_text("Mobile No", mobile)
        self.ui.replace_text("Email", email)
        self.ui.replace_text("Address", address)
        self.ui.keyevent("4")
        time.sleep(0.5)
        self.ui.tap("content-desc", "Save")
        self._wait_for_local_value(
            lambda: code in self.customer_codes(),
            f"customer {code}",
        )

    def select_customer(self, code: str) -> None:
        self._reveal_hint("Customer", direction="up")
        customer_fields = [
            node
            for node in self.ui.nodes()
            if "Customer" in node.attributes.get("hint", "")
            and node.attributes.get("class") == "android.widget.EditText"
        ]
        if customer_fields and customer_fields[0].attributes.get("text", ""):
            x, y = suffix_icon_tap_position(customer_fields[0])
            self.shell("input", "tap", str(x), str(y))
            time.sleep(0.5)
        self.ui.replace_text("Customer", code)
        self.hide_keyboard_if_visible()
        result = self.ui.wait("content-desc", code, exact=False, timeout=15)
        if result.attributes.get("clickable") != "true":
            candidates = [
                node
                for node in self.ui.nodes()
                if code in node.attributes.get("content-desc", "")
                and node.attributes.get("clickable") == "true"
            ]
            if not candidates:
                raise RuntimeError(f"No customer search result for {code}")
            result = candidates[-1]
        self.ui.tap_node(result)
        time.sleep(0.8)

    def record_sale(self, *, barcode: str, customer_code: str | None) -> None:
        previous_outgoing_sales = self.state().outgoing_sale_count
        self.navigate("Sales")
        self._focus_compact_body()
        self._position_compact_sales(at_top=True)
        self._reveal_hint("Search / Scan Item", direction="down")
        self.ui.replace_text("Search / Scan Item", barcode)
        self.hide_keyboard_if_visible()
        self._position_compact_sales(at_top=True)
        self._reveal_description("Add Exact Match", direction="down")
        self.ui.tap("content-desc", "Add Exact Match")
        time.sleep(0.8)
        if customer_code is not None:
            self._position_compact_sales(at_top=False)
            self.select_customer(customer_code)
        self._position_compact_sales(at_top=False)
        for _ in range(3):
            self._reveal_description("Record Sale", direction="up")
            self.ui.tap("content-desc", "Record Sale")
            try:
                self._wait_for_local_value(
                    lambda: self.state().outgoing_sale_count
                    > previous_outgoing_sales,
                    "finalized sale event",
                    timeout=8,
                )
                break
            except AssertionError:
                self.hide_keyboard_if_visible()
        else:
            raise AssertionError("Timed out waiting for local finalized sale event")
        time.sleep(0.7)

    def _focus_compact_body(self) -> None:
        size = self.shell("wm", "size")
        physical = size.rsplit(":", 1)[-1].strip()
        width, height = (int(value) for value in physical.split("x"))
        if width >= 1400:
            return
        for _ in range(2):
            # Use the shell padding so the outer ListView, rather than the
            # nested sales list, receives the gesture.
            self.ui.swipe(20, height - 200, 20, 300, 700)
            time.sleep(0.6)

    def _position_compact_sales(self, *, at_top: bool) -> None:
        size = self.shell("wm", "size")
        physical = size.rsplit(":", 1)[-1].strip()
        width, _ = (int(value) for value in physical.split("x"))
        if width >= 1400:
            return
        target = self._content_scroller()
        left, top, right, bottom = target.bounds
        x = (left + right) // 2
        margin = min(80, max(30, (bottom - top) // 4))
        for _ in range(5):
            if at_top:
                self.ui.swipe(x, top + margin, x, bottom - margin, 500)
            else:
                self.ui.swipe(x, bottom - margin, x, top + margin, 500)
            time.sleep(0.35)

    def hide_keyboard_if_visible(self) -> None:
        input_method_state = self.shell("dumpsys", "input_method")
        if not input_method_is_shown(input_method_state):
            return
        self.ui.keyevent("4")
        time.sleep(1)

    def _is_foreground(self) -> bool:
        activity_state = self.shell("dumpsys", "activity", "activities")
        return package_is_resumed(activity_state, PACKAGE)

    def _reveal_hint(self, hint: str, *, direction: str) -> None:
        for _ in range(7):
            try:
                self.ui.find("hint", hint, exact=False)
                return
            except RuntimeError:
                self._scroll(direction)
        raise RuntimeError(f"Cannot reveal field {hint!r} on {self.serial}")

    def _reveal_description(self, value: str, *, direction: str) -> None:
        for _ in range(7):
            try:
                self.ui.find("content-desc", value, exact=False)
                return
            except RuntimeError:
                self._scroll(direction)
        raise RuntimeError(f"Cannot reveal {value!r} on {self.serial}")

    def _scroll(self, direction: str) -> None:
        target = self._content_scroller()
        left, top, right, bottom = target.bounds
        x = (left + right) // 2
        margin = min(80, max(30, (bottom - top) // 4))
        if direction == "up":
            self.ui.swipe(x, bottom - margin, x, top + margin, 600)
        else:
            self.ui.swipe(x, top + margin, x, bottom - margin, 600)
        time.sleep(0.7)

    def _content_scroller(self) -> UiNode:
        size = self.shell("wm", "size")
        physical = size.rsplit(":", 1)[-1].strip()
        width, height = (int(value) for value in physical.split("x"))
        candidates = []
        for node in self.ui.nodes():
            if node.attributes.get("scrollable") != "true":
                continue
            left, top, right, bottom = node.bounds
            node_width = right - left
            node_height = bottom - top
            if node_width < width * 0.6 or bottom < height * 0.75:
                continue
            if node_height < 160:
                continue
            candidates.append((node_width * node_height, node))
        if not candidates:
            raise RuntimeError(f"No content scroller is visible on {self.serial}")
        _, target = min(candidates, key=lambda candidate: candidate[0])
        return target

    def _wait_for_local_value(
        self,
        predicate,
        description: str,
        *,
        timeout: float = 20,
    ) -> None:
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            if predicate():
                return
            time.sleep(0.8)
        raise AssertionError(f"Timed out waiting for local {description}")

    def copy_database(self) -> Path:
        destination = Path(tempfile.mkdtemp(prefix=f"neuradix-{self.label}-"))
        listing = self.shell("run-as", PACKAGE, "ls", "databases")
        for suffix in ("", "-wal", "-shm"):
            name = f"{DATABASE}{suffix}"
            if name not in listing.split():
                continue
            output = destination / name
            with output.open("wb") as target:
                subprocess.run(
                    [
                        self.adb,
                        "-s",
                        self.serial,
                        "exec-out",
                        "run-as",
                        PACKAGE,
                        "cat",
                        f"databases/{name}",
                    ],
                    check=True,
                    stdout=target,
                    timeout=30,
                )
        return destination

    def state(self) -> RegisterState:
        copied = self.copy_database()
        try:
            connection = sqlite3.connect(copied / DATABASE)
            connection.row_factory = sqlite3.Row
            profile = connection.execute(
                """
                SELECT business_id, shop_id, shop_name, device_id
                FROM local_sync_profile WHERE profile_id = 1
                """
            ).fetchone()
            if profile is None:
                raise RuntimeError(f"{self.serial} has no local sync profile")
            count = lambda table: connection.execute(
                f'SELECT COUNT(*) FROM "{table}"'
            ).fetchone()[0]
            pending = connection.execute(
                """
                SELECT COUNT(*) FROM local_sync_events
                WHERE direction = 'outgoing'
                  AND status IN ('pending', 'retry', 'sent')
                """
            ).fetchone()[0]
            outgoing_sales = connection.execute(
                """
                SELECT COUNT(*) FROM local_sync_events
                WHERE direction = 'outgoing'
                  AND entity_type = 'finalized_sale'
                """
            ).fetchone()[0]
            return RegisterState(
                business_id=profile["business_id"],
                shop_id=profile["shop_id"],
                shop_name=profile["shop_name"],
                device_id=profile["device_id"],
                item_count=count("hosted_inventory_items"),
                customer_count=count("hosted_customers"),
                sale_count=count("hosted_sales"),
                outgoing_sale_count=outgoing_sales,
                pending_count=pending,
            )
        finally:
            connection.close()
            shutil.rmtree(copied)

    def customer_codes(self) -> set[str]:
        copied = self.copy_database()
        connection = sqlite3.connect(copied / DATABASE)
        try:
            return {
                str(row[0])
                for row in connection.execute(
                    "SELECT customer_code FROM hosted_customers"
                ).fetchall()
            }
        finally:
            connection.close()
            shutil.rmtree(copied)

    def inventory_skus(self) -> set[str]:
        copied = self.copy_database()
        connection = sqlite3.connect(copied / DATABASE)
        try:
            return {
                str(row[0])
                for row in connection.execute(
                    "SELECT sku FROM hosted_inventory_items"
                ).fetchall()
            }
        finally:
            connection.close()
            shutil.rmtree(copied)


def wait_for_state(
    register: Register,
    predicate,
    description: str,
    timeout: float = 45,
) -> RegisterState:
    deadline = time.monotonic() + timeout
    last = register.state()
    while time.monotonic() < deadline:
        last = register.state()
        if predicate(last):
            return last
        time.sleep(2)
    raise AssertionError(f"Timed out waiting for {description}; last state: {last}")


def add_sales(
    register: Register,
    *,
    count: int,
    barcode: str,
    customer_code: str,
) -> None:
    for index in range(count):
        register.record_sale(
            barcode=barcode,
            customer_code=customer_code if index == 0 else None,
        )


def assert_boundaries(a: RegisterState, b: RegisterState, sales: int) -> None:
    if a.item_count != 4 or b.item_count != 4:
        raise AssertionError(f"Inventory boundary failed: A={a}, B={b}")
    if a.customer_count != 6 or b.customer_count != 6:
        raise AssertionError(f"Customer convergence failed: A={a}, B={b}")
    if a.sale_count != sales or b.sale_count != sales:
        raise AssertionError(f"Sale convergence failed: A={a}, B={b}")


def build_certification_result(
    *,
    run_id: str,
    timestamp_utc: str,
    a: RegisterState,
    b: RegisterState,
) -> dict[str, object]:
    expected = {
        "sales_per_register": 18,
        "customers_per_register": 6,
        "items_per_register": 4,
        "pending_per_register": 0,
    }
    for label, state in (("shop_a", a), ("shop_b", b)):
        actual = {
            "sales_per_register": state.sale_count,
            "customers_per_register": state.customer_count,
            "items_per_register": state.item_count,
            "pending_per_register": state.pending_count,
        }
        if actual != expected:
            raise AssertionError(
                f"Cannot publish inconsistent certification result for {label}: "
                f"expected={expected}, actual={actual}"
            )
    return {
        "timestamp_utc": timestamp_utc,
        "run_id": run_id,
        "business_id": a.business_id,
        "shop_a": a.__dict__,
        "shop_b": b.__dict__,
        "expected": expected,
    }


def mixed_mode_is_complete(a: RegisterState, b: RegisterState) -> bool:
    return (
        a.outgoing_sale_count >= 9
        and b.outgoing_sale_count >= 9
        and a.sale_count >= 18
        and b.sale_count >= 18
    )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--serial-a", default="emulator-5554")
    parser.add_argument("--serial-b", default="emulator-5556")
    parser.add_argument("--adb", default=DEFAULT_ADB)
    parser.add_argument(
        "--output",
        type=Path,
        default=Path("docs/test-results/screenshots/local_multi_shop_2026-09-29"),
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    a = Register(args.serial_a, "shop_a", args.adb, args.output)
    b = Register(args.serial_b, "shop_b", args.adb, args.output)
    for register in (a, b):
        # Start disconnected so a resumed certification run cannot flush a
        # pending outbox before durability assertions inspect it.
        register.set_online(False)
        register.launch()

    initial_a, initial_b = a.state(), b.state()
    if initial_a.business_id != initial_b.business_id:
        raise AssertionError("Registers belong to different businesses")
    if initial_a.shop_id == initial_b.shop_id:
        raise AssertionError("Registers must be assigned to different shops")
    if initial_a.customer_count > 6 or initial_b.customer_count > 6:
        raise AssertionError("Certification setup has unexpected customer data")
    if initial_a.sale_count > 18 or initial_b.sale_count > 18:
        raise AssertionError("Certification setup has unexpected sale data")
    if initial_a.outgoing_sale_count > 9 or initial_b.outgoing_sale_count > 9:
        raise AssertionError("Certification setup has unexpected local sales")
    if initial_a.item_count > 4 or initial_b.item_count > 4:
        raise AssertionError("Certification setup has unexpected inventory data")

    timestamp = datetime.now(timezone.utc).strftime("%H%M%S")
    for register, prefix, existing in (
        (a, "A", initial_a.item_count),
        (b, "B", initial_b.item_count),
    ):
        for index in range(existing + 1, 5):
            register.create_item(
                sku=f"CERT-{prefix}-{index}",
                barcode=f"535300{1 if prefix == 'A' else 2}{index:05d}",
                name=f"Certification {prefix} Item {index}",
                price=f"{index + 1}.50",
                stock=str(100 - index),
            )
    a.screenshot("03_isolated_inventory")
    b.screenshot("03_isolated_inventory")
    time.sleep(4)
    isolated_a, isolated_b = a.state(), b.state()
    if isolated_a.item_count != 4 or isolated_b.item_count != 4:
        raise AssertionError(f"Shop inventory leaked or failed: {isolated_a}, {isolated_b}")

    # Both offline: six customers and six sales remain durable in local outboxes.
    a.set_online(False)
    b.set_online(False)
    for register, prefix in ((a, "A"), (b, "B")):
        existing_codes = register.customer_codes()
        for index in range(1, 4):
            customer_code = f"CERT-{prefix}-C{index}"
            if customer_code in existing_codes:
                continue
            register.create_customer(
                code=customer_code,
                name=f"Certification {prefix} Customer {index}",
                mobile=f"7700{1 if prefix == 'A' else 2}{index:03d}",
                email=f"cert-{prefix.lower()}-{index}@example.test",
                address=f"Certification {prefix} Address {index}",
            )
        current = register.state()
        remaining_offline_sales = 3 - current.outgoing_sale_count
        if remaining_offline_sales > 0:
            add_sales(
                register,
                count=remaining_offline_sales,
                barcode=f"535300{1 if prefix == 'A' else 2}00001",
                customer_code=f"CERT-{prefix}-C1",
            )
    a.screenshot("04_both_offline_queued")
    b.screenshot("04_both_offline_queued")
    offline_a, offline_b = a.state(), b.state()
    pending_source = a if offline_a.pending_count >= offline_b.pending_count else b
    pending_before_restart = pending_source.state().pending_count
    if pending_before_restart >= 3:
        pending_source.restart()
        if pending_source.state().pending_count < pending_before_restart:
            raise AssertionError(
                "Pending events were lost across application restart"
            )
    elif not (
        offline_a.outgoing_sale_count >= 3
        and offline_b.outgoing_sale_count >= 3
        and offline_a.sale_count >= 6
        and offline_b.sale_count >= 6
    ):
        raise AssertionError("Offline events were not retained in an outbox")

    a.set_online(True)
    b.set_online(True)
    offline_target = a.state().outgoing_sale_count + b.state().outgoing_sale_count
    wait_for_state(
        a,
        lambda state: state.sale_count == offline_target,
        "offline sales on A",
    )
    wait_for_state(
        b,
        lambda state: state.sale_count == offline_target,
        "offline sales on B",
    )
    assert_boundaries(a.state(), b.state(), offline_target)

    # Both online: three more sales from each shop should converge immediately.
    add_sales(
        a,
        count=max(0, 6 - a.state().outgoing_sale_count),
        barcode="535300100001",
        customer_code="CERT-A-C2",
    )
    add_sales(
        b,
        count=max(0, 6 - b.state().outgoing_sale_count),
        barcode="535300200001",
        customer_code="CERT-B-C2",
    )
    online_target = a.state().outgoing_sale_count + b.state().outgoing_sale_count
    wait_for_state(
        a,
        lambda state: state.sale_count == online_target,
        "online sales on A",
    )
    wait_for_state(
        b,
        lambda state: state.sale_count == online_target,
        "online sales on B",
    )
    assert_boundaries(a.state(), b.state(), online_target)

    # Mixed: Shop A is offline, Shop B stays online, and both continue selling.
    if not mixed_mode_is_complete(a.state(), b.state()):
        a.set_online(False)
        add_sales(
            a,
            count=max(0, 9 - a.state().outgoing_sale_count),
            barcode="535300100001",
            customer_code="CERT-A-C3",
        )
        add_sales(
            b,
            count=max(0, 9 - b.state().outgoing_sale_count),
            barcode="535300200001",
            customer_code="CERT-B-C3",
        )
        b.restart()
        if b.state().pending_count < 3:
            raise AssertionError(
                "Unacknowledged mixed-mode events were lost on restart"
            )
    a.set_online(True)
    wait_for_state(a, lambda state: state.sale_count == 18, "mixed sales on A", 60)
    wait_for_state(b, lambda state: state.sale_count == 18, "mixed sales on B", 60)
    final_a, final_b = a.state(), b.state()
    assert_boundaries(final_a, final_b, 18)
    final_a = wait_for_state(
        a,
        lambda state: state.pending_count == 0,
        "A acknowledgements",
    )
    final_b = wait_for_state(
        b,
        lambda state: state.pending_count == 0,
        "B acknowledgements",
    )
    a.screenshot("05_final_convergence")
    b.screenshot("05_final_convergence")

    result = build_certification_result(
        run_id=timestamp,
        timestamp_utc=datetime.now(timezone.utc).isoformat(),
        a=final_a,
        b=final_b,
    )
    result_path = args.output.parent / "local_multi_shop_server_e2e_result.json"
    result_path.write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps(result, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
