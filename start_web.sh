#!/usr/bin/env bash
set -euo pipefail

CASSAR_URL="${NEURADIX_DEFAULT_URL:-http://neuradix-cassar.localhost:8008}"
CLOUD_URL="${NEURADIX_CLOUD_URL:-http://neuradix-cloud.localhost:8018}"

cd /Users/trek-matrix/Work/Kevins_work/neuradix-pos
flutter run -d web-server \
  --web-hostname 127.0.0.1 \
  --web-port 3000 \
  --dart-define=NEURADIX_DEFAULT_URL="$CASSAR_URL" \
  --dart-define=NEURADIX_CLOUD_URL="$CLOUD_URL"
