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

PDF_PYTHON="python3"
if ! "$PDF_PYTHON" -c 'import reportlab, pypdf' >/dev/null 2>&1; then
  BUNDLED_PYTHON="$HOME/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3"
  if [[ ! -x "$BUNDLED_PYTHON" ]]; then
    echo "[pdf] reportlab and pypdf are required to generate documentation" >&2
    exit 1
  fi
  PDF_PYTHON="$BUNDLED_PYTHON"
fi

"$PDF_PYTHON" tool/docs/generate_local_multi_shop_pdfs.py
"$PDF_PYTHON" tool/docs/validate_local_multi_shop_pdfs.py
"$PDF_PYTHON" -m unittest discover -s test/tool -p 'test_*.py'
