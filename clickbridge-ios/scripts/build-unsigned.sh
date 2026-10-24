#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/device
python3 scripts/generate_project.py
xcodebuild -project ClickBridge.xcodeproj -scheme ClickBridge -configuration Release \
  -destination 'generic/platform=iOS' -derivedDataPath build/DeviceData \
  CODE_SIGNING_ALLOWED=NO build > build/device/build.log 2>&1 || {
    tail -100 build/device/build.log; exit 1;
  }
python3 - <<'PY'
from pathlib import Path
import hashlib,json,plistlib,zipfile
app=Path('build/DeviceData/Build/Products/Release-iphoneos/ClickBridge.app')
info=plistlib.loads((app/'Info.plist').read_bytes())
assert info['CFBundleIdentifier']=='de.p1337.ClickBridge'
assert not (app/'embedded.mobileprovision').exists()
out=Path('build/device/ClickBridge-UNSIGNED.ipa')
with zipfile.ZipFile(out,'w',compression=zipfile.ZIP_DEFLATED) as z:
    for file in sorted(app.rglob('*')):
        if file.is_file(): z.write(file,Path('Payload/ClickBridge.app')/file.relative_to(app))
record={'bundleID':info['CFBundleIdentifier'],'signed':False,'installableWithoutResigning':False,
        'sha256':hashlib.sha256(out.read_bytes()).hexdigest()}
Path('build/device/build-record.json').write_text(json.dumps(record,indent=2)+'\n')
print('UNSIGNED IPA built; requires valid signing before installation.')
PY
