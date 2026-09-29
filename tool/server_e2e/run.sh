#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ADB="${ADB:-/Users/trek-matrix/Library/Android/sdk/platform-tools/adb}"
SERIAL_A="${NEURADIX_E2E_SERIAL_A:-emulator-5554}"
SERIAL_B="${NEURADIX_E2E_SERIAL_B:-emulator-5556}"

cd "$REPO_ROOT"
"$ADB" -s "$SERIAL_A" get-state >/dev/null
"$ADB" -s "$SERIAL_B" get-state >/dev/null

python3 tool/server_e2e/local_multi_shop_server_e2e.py \
  --adb "$ADB" \
  --serial-a "$SERIAL_A" \
  --serial-b "$SERIAL_B"

echo "[server-e2e] Auditing deployed storage boundary"
if [[ -n "${NEURADIX_E2E_SERVER_AUDIT_COMMAND:-}" ]]; then
  bash -lc "$NEURADIX_E2E_SERVER_AUDIT_COMMAND"
else
  python3 tool/server_e2e/audit_server_storage.py
fi
