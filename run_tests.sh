#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="/Users/trek-matrix/Work/Kevins_work/neuradix-pos"

cd "$REPO_ROOT"
flutter pub get
dart format --set-exit-if-changed lib test
flutter analyze
if rg -n "build_runner" pubspec.yaml >/dev/null 2>&1; then
  dart run build_runner build --delete-conflicting-outputs
else
  echo "[generated-code] no build_runner configuration detected"
fi
flutter test
