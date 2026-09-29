#!/usr/bin/env python3
"""Small dependency-free accessibility driver for Neuradix Android E2E tests."""

from __future__ import annotations

import argparse
import os
import re
import subprocess
import sys
import time
import xml.etree.ElementTree as ET
from dataclasses import dataclass
from pathlib import Path


DEFAULT_ADB = os.environ.get(
    "ADB",
    "/Users/trek-matrix/Library/Android/sdk/platform-tools/adb",
)


def encode_adb_text(value: str) -> str:
    """Encode text for Android's `input text` command.

    Android treats spaces as argument separators even when adb receives one
    host-side argument. `%s` is the input command's portable space escape.
    The acceptance data intentionally stays within this conservative set.
    """

    return value.replace("%", "%25").replace(" ", "%s")


def text_field_tap_position(node: "UiNode") -> tuple[int, int]:
    """Return the editable region inside a Flutter semantics node.

    Compact Flutter layouts can merge an EditText and its autocomplete rows
    into one tall accessibility node. The editable control remains near the
    top of that node, so tapping its geometric center may select a result row.
    """

    left, top, right, bottom = node.bounds
    x = (left + right) // 2
    hint = node.attributes.get("hint", "")
    if "\n" in hint and bottom - top > 250:
        node_width = right - left
        node_height = bottom - top
        offset = 180 if node_height > node_width else 132
        return x, min(bottom - 20, top + offset)
    return x, (top + bottom) // 2


def suffix_icon_tap_position(node: "UiNode") -> tuple[int, int]:
    _, _, right, _ = node.bounds
    _, field_y = text_field_tap_position(node)
    return right - 48, field_y


@dataclass(frozen=True)
class UiNode:
    attributes: dict[str, str]

    @property
    def bounds(self) -> tuple[int, int, int, int]:
        values = [int(value) for value in re.findall(r"\d+", self.attributes["bounds"])]
        if len(values) != 4:
            raise RuntimeError(f"Invalid node bounds: {self.attributes['bounds']}")
        return values[0], values[1], values[2], values[3]

    @property
    def center(self) -> tuple[int, int]:
        left, top, right, bottom = self.bounds
        return (left + right) // 2, (top + bottom) // 2


class AdbUi:
    def __init__(self, serial: str, adb: str = DEFAULT_ADB) -> None:
        self.serial = serial
        self.adb = adb

    def _run(
        self,
        *args: str,
        capture_output: bool = True,
        timeout: float = 30,
    ) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [self.adb, "-s", self.serial, *args],
            check=True,
            capture_output=capture_output,
            text=True,
            timeout=timeout,
        )

    def shell(self, *args: str, timeout: float = 30) -> str:
        return self._run("shell", *args, timeout=timeout).stdout

    def dump(self) -> ET.Element:
        self.shell("uiautomator", "dump", "/sdcard/window.xml")
        payload = self.shell("cat", "/sdcard/window.xml")
        return ET.fromstring(payload)

    def nodes(self) -> list[UiNode]:
        return [UiNode(dict(node.attrib)) for node in self.dump().iter("node")]

    def find(
        self,
        attribute: str,
        value: str,
        *,
        exact: bool = True,
        clickable: bool | None = None,
    ) -> UiNode:
        matches: list[UiNode] = []
        for node in self.nodes():
            candidate = node.attributes.get(attribute, "")
            matched = candidate == value if exact else value in candidate
            if not matched:
                continue
            if clickable is not None:
                expected = "true" if clickable else "false"
                if node.attributes.get("clickable") != expected:
                    continue
            matches.append(node)
        if not matches:
            raise RuntimeError(
                f"No visible node matched {attribute}={value!r} on {self.serial}"
            )
        return matches[0]

    def tap_node(self, node: UiNode) -> None:
        x, y = node.center
        self.shell("input", "tap", str(x), str(y))

    def tap(self, attribute: str, value: str, *, exact: bool = True) -> None:
        self.tap_node(self.find(attribute, value, exact=exact, clickable=True))

    def wait(
        self,
        attribute: str,
        value: str,
        *,
        exact: bool = True,
        timeout: float = 20,
    ) -> UiNode:
        deadline = time.monotonic() + timeout
        last_error: Exception | None = None
        while time.monotonic() < deadline:
            try:
                return self.find(attribute, value, exact=exact)
            except (RuntimeError, subprocess.SubprocessError, ET.ParseError) as error:
                last_error = error
                time.sleep(0.5)
        raise RuntimeError(
            f"Timed out waiting for {attribute}={value!r} on {self.serial}: {last_error}"
        )

    def replace_text(
        self,
        hint: str,
        value: str,
        *,
        chunk_size: int = 24,
        chunk_delay: float = 0.35,
    ) -> None:
        try:
            field = self.find("hint", hint)
        except RuntimeError:
            candidates = [
                node
                for node in self.nodes()
                if hint in node.attributes.get("hint", "")
                and node.attributes.get("class") == "android.widget.EditText"
            ]
            if not candidates:
                raise RuntimeError(
                    f"No editable field matched hint={hint!r} on {self.serial}"
                )
            field = candidates[0]
        x, y = text_field_tap_position(field)
        self.shell("input", "tap", str(x), str(y))
        time.sleep(0.5)
        self.shell("input", "keycombination", "113", "29")
        time.sleep(0.4)
        for offset in range(0, len(value), chunk_size):
            self.shell(
                "input",
                "text",
                encode_adb_text(value[offset : offset + chunk_size]),
            )
            time.sleep(chunk_delay)

    def keyevent(self, keycode: str) -> None:
        self.shell("input", "keyevent", keycode)

    def swipe(self, x1: int, y1: int, x2: int, y2: int, duration_ms: int) -> None:
        self.shell(
            "input",
            "swipe",
            str(x1),
            str(y1),
            str(x2),
            str(y2),
            str(duration_ms),
        )

    def screenshot(self, output: Path) -> None:
        output.parent.mkdir(parents=True, exist_ok=True)
        with output.open("wb") as target:
            subprocess.run(
                [self.adb, "-s", self.serial, "exec-out", "screencap", "-p"],
                check=True,
                stdout=target,
                timeout=30,
            )


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser()
    parser.add_argument("--serial", required=True)
    parser.add_argument("--adb", default=DEFAULT_ADB)
    subparsers = parser.add_subparsers(dest="command", required=True)

    for command in ("tap-desc", "tap-text", "tap-hint", "wait-desc"):
        subparser = subparsers.add_parser(command)
        subparser.add_argument("value")
        subparser.add_argument("--contains", action="store_true")
        if command == "wait-desc":
            subparser.add_argument("--timeout", type=float, default=20)

    replace = subparsers.add_parser("set-hint")
    replace.add_argument("hint")
    replace.add_argument("value")

    swipe = subparsers.add_parser("swipe")
    swipe.add_argument("x1", type=int)
    swipe.add_argument("y1", type=int)
    swipe.add_argument("x2", type=int)
    swipe.add_argument("y2", type=int)
    swipe.add_argument("duration_ms", type=int)

    keyevent = subparsers.add_parser("keyevent")
    keyevent.add_argument("keycode")

    screenshot = subparsers.add_parser("screenshot")
    screenshot.add_argument("output", type=Path)

    subparsers.add_parser("dump")
    return parser


def main() -> int:
    args = _parser().parse_args()
    ui = AdbUi(args.serial, args.adb)
    if args.command == "tap-desc":
        ui.tap("content-desc", args.value, exact=not args.contains)
    elif args.command == "tap-text":
        ui.tap("text", args.value, exact=not args.contains)
    elif args.command == "tap-hint":
        ui.tap("hint", args.value, exact=not args.contains)
    elif args.command == "wait-desc":
        node = ui.wait(
            "content-desc",
            args.value,
            exact=not args.contains,
            timeout=args.timeout,
        )
        print(node.attributes.get("content-desc", ""))
    elif args.command == "set-hint":
        ui.replace_text(args.hint, args.value)
    elif args.command == "swipe":
        ui.swipe(args.x1, args.y1, args.x2, args.y2, args.duration_ms)
    elif args.command == "keyevent":
        ui.keyevent(args.keycode)
    elif args.command == "screenshot":
        ui.screenshot(args.output)
    elif args.command == "dump":
        ET.dump(ui.dump())
    else:
        raise RuntimeError(f"Unsupported command: {args.command}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (RuntimeError, subprocess.SubprocessError, ET.ParseError) as error:
        print(error, file=sys.stderr)
        raise SystemExit(1) from error
