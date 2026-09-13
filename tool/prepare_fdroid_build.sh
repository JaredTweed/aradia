#!/usr/bin/env sh
set -eu

# Google Cast uses proprietary Play Services. The F-Droid build keeps the Dart
# API and UI intact, but substitutes a source-only no-op package.
python3 - <<'PY'
from pathlib import Path
p = Path('pubspec.yaml')
s = p.read_text()
old = '  flutter_chrome_cast: ^1.2.5\n'
new = '  flutter_chrome_cast:\n    path: third_party/fdroid_chrome_cast_stub\n'
if old not in s:
    raise SystemExit('expected flutter_chrome_cast dependency was not found')
p.write_text(s.replace(old, new, 1))
PY
