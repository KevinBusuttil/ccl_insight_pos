#!/usr/bin/env bash
set -euo pipefail

CASSAR_URL="${NEURADIX_DEFAULT_URL:-http://127.0.0.1:8008}"
CLOUD_URL="${NEURADIX_CLOUD_URL:-http://127.0.0.1:8018}"

cd /Users/trek-matrix/Work/Kevins_work/neuradix-pos
flutter run -d macos \
  --dart-define=NEURADIX_DEFAULT_URL="$CASSAR_URL" \
  --dart-define=NEURADIX_CLOUD_URL="$CLOUD_URL"
