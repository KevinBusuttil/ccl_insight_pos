#!/usr/bin/env python3
"""Fail when a Local Multi-Shop business has hosted operational rows."""

from __future__ import annotations

import argparse
import json
import os
import re
import shlex
import subprocess
from datetime import datetime, timezone
from pathlib import Path


EXPECTED_TABLES = (
    "Neuradix Product",
    "Neuradix Customer",
    "Neuradix Sale",
    "Neuradix Sale Item",
)
BUSINESS_ID_PATTERN = re.compile(r"^[A-Za-z0-9_-]+$")


def build_audit_sql(business_id: str) -> str:
    if not BUSINESS_ID_PATTERN.fullmatch(business_id):
        raise ValueError(f"Unsafe business id: {business_id!r}")
    return (
        'SELECT "Neuradix Product", COUNT(*) FROM `tabNeuradix Product` '
        f'WHERE business="{business_id}" UNION ALL '
        'SELECT "Neuradix Customer", COUNT(*) FROM `tabNeuradix Customer` '
        f'WHERE business="{business_id}" UNION ALL '
        'SELECT "Neuradix Sale", COUNT(*) FROM `tabNeuradix Sale` '
        f'WHERE business="{business_id}" UNION ALL '
        'SELECT "Neuradix Sale Item", COUNT(*) FROM `tabNeuradix Sale Item` '
        'WHERE parent IN (SELECT name FROM `tabNeuradix Sale` '
        f'WHERE business="{business_id}");'
    )


def parse_audit_output(output: str) -> dict[str, int]:
    counts: dict[str, int] = {}
    for line in output.splitlines():
        if not line.strip():
            continue
        parts = line.rsplit("\t", 1)
        if len(parts) != 2:
            raise ValueError(f"Unexpected SQL audit row: {line!r}")
        table, raw_count = parts
        if table not in EXPECTED_TABLES:
            raise ValueError(f"Unexpected SQL audit table: {table!r}")
        counts[table] = int(raw_count)
    missing = set(EXPECTED_TABLES) - counts.keys()
    if missing:
        raise ValueError(f"SQL audit omitted tables: {sorted(missing)}")
    return counts


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--result",
        type=Path,
        default=Path(
            "docs/test-results/screenshots/local_multi_shop_server_e2e_result.json"
        ),
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=Path(
            "docs/test-results/screenshots/local_multi_shop_server_storage_audit.json"
        ),
    )
    parser.add_argument(
        "--ssh-host",
        default=os.environ.get(
            "NEURADIX_E2E_SSH_HOST", "frappe@167.172.37.224"
        ),
    )
    parser.add_argument(
        "--identity-file",
        default=os.environ.get(
            "NEURADIX_E2E_SSH_KEY",
            "/Users/trek-matrix/.ssh/codex_neuradix_cloud_setup",
        ),
    )
    parser.add_argument(
        "--remote-bench",
        default=os.environ.get(
            "NEURADIX_E2E_REMOTE_BENCH", "/home/frappe/neuradix-cloud-bench"
        ),
    )
    parser.add_argument(
        "--site",
        default=os.environ.get("NEURADIX_E2E_SITE", "neuradix-cloud.localhost"),
    )
    parser.add_argument(
        "--bench-command",
        default=os.environ.get(
            "NEURADIX_E2E_BENCH_COMMAND", "/home/frappe/.local/bin/bench"
        ),
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    result = json.loads(args.result.read_text())
    business_id = str(result["business_id"])
    sql = build_audit_sql(business_id)
    remote_command = (
        f"cd {shlex.quote(args.remote_bench)} && "
        f"{shlex.quote(args.bench_command)} --site {shlex.quote(args.site)} "
        f"mariadb -N -e {shlex.quote(sql)}"
    )
    command = [
        "ssh",
        "-o",
        "IdentitiesOnly=yes",
        "-o",
        "ConnectTimeout=15",
    ]
    if args.identity_file:
        command.extend(["-i", args.identity_file])
    command.extend([args.ssh_host, remote_command])
    completed = subprocess.run(
        command,
        check=True,
        capture_output=True,
        text=True,
        timeout=60,
    )
    counts = parse_audit_output(completed.stdout)
    nonzero = {table: count for table, count in counts.items() if count != 0}
    audit = {
        "timestamp_utc": datetime.now(timezone.utc).isoformat(),
        "business_id": business_id,
        "counts": counts,
        "passed": not nonzero,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(audit, indent=2) + "\n")
    if nonzero:
        raise AssertionError(
            f"Local Multi-Shop business persisted operational rows: {nonzero}"
        )
    print(json.dumps(audit, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
