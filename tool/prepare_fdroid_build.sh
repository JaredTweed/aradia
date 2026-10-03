#!/usr/bin/env sh
set -eu

# Google Cast uses proprietary Play Services. Disable its UI and native
# declarations as well as substituting a source-only compatibility package.
python3 - <<'PY'
from pathlib import Path
p = Path('pubspec.yaml')
s = p.read_text()
old = '  flutter_chrome_cast: ^1.2.5\n'
new = '  flutter_chrome_cast:\n    path: third_party/fdroid_chrome_cast_stub\n'
if old not in s:
    raise SystemExit('expected flutter_chrome_cast dependency was not found')
p.write_text(s.replace(old, new, 1))

features = Path('lib/config/build_features.dart')
features.write_text('/// F-Droid builds do not include Google Cast.\n'
                    'const supportsGoogleCast = false;\n')

import xml.etree.ElementTree as ET
android = '{http://schemas.android.com/apk/res/android}'
ET.register_namespace('android', android[1:-1])
ET.register_namespace('tools', 'http://schemas.android.com/tools')
manifest = Path('android/app/src/main/AndroidManifest.xml')
tree = ET.parse(manifest)
root = tree.getroot()
cast_permissions = {
    'android.permission.ACCESS_WIFI_STATE',
    'android.permission.CHANGE_WIFI_MULTICAST_STATE',
    'android.permission.ACCESS_FINE_LOCATION',
    'android.permission.ACCESS_COARSE_LOCATION',
}
for permission in list(root.findall('uses-permission')):
    if permission.get(android + 'name') in cast_permissions:
        root.remove(permission)
application = root.find('application')
for entry in list(application):
    if entry.get(android + 'name', '').startswith('com.google.android.gms.cast.'):
        application.remove(entry)
tree.write(manifest, encoding='unicode')
PY
cp tool/fdroid.pubspec.lock pubspec.lock
