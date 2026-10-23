#!/bin/bash
set -euo pipefail
kit_root="$(cd "$(dirname "$0")/.." && pwd)"
upstream_root="${1:?Supply the clean pinned incyclist/mobile checkout}"
evidence_dir="$kit_root/build/incyclist"
mkdir -p "$evidence_dir"
test -d "${DEVELOPER_DIR:?Xcode 26.3 must be selected}"
xcodebuild -version | tee "$evidence_dir/toolchain.txt"
python3 "$kit_root/integrations/incyclist/install.py" "$upstream_root"
cd "$upstream_root"
git diff --check
plutil -lint ios/Incyclist.xcodeproj/project.pbxproj ios/Incyclist/Info.plist ios/Incyclist/PrivacyInfo.xcprivacy
node --test src/integrations/clickbridge/shiftRouter.test.cjs | tee "$evidence_dir/routing-tests.log"
npm ci --ignore-scripts > "$evidence_dir/npm.log" 2>&1 || { tail -60 "$evidence_dir/npm.log"; exit 1; }
node_modules/.bin/patch-package > "$evidence_dir/patches.log" 2>&1 || { tail -60 "$evidence_dir/patches.log"; exit 1; }
# Scope the typecheck to this adapter and actual installed Incyclist declarations.
cat > tsconfig.clickbridge.json <<'JSON'
{
  "extends": "./tsconfig.json",
  "compilerOptions": {"noEmit": true, "skipLibCheck": true},
  "include": ["src/integrations/clickbridge/ClickBridgeControls.tsx", "src/integrations/clickbridge/shiftRouter.d.ts"]
}
JSON
node_modules/.bin/tsc -p tsconfig.clickbridge.json > "$evidence_dir/typecheck.log" 2>&1 || { cat "$evidence_dir/typecheck.log"; exit 1; }
mkdir -p config
if [ ! -f config/config.json ]; then printf '{}\n' > config/config.json; fi
cd ios
pod install > "$evidence_dir/pods.log" 2>&1 || { tail -100 "$evidence_dir/pods.log"; exit 1; }
cd ..
xcodebuild -workspace ios/Incyclist.xcworkspace -scheme Incyclist -configuration Debug \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath "$evidence_dir/DerivedData" \
  CODE_SIGNING_ALLOWED=NO ONLY_ACTIVE_ARCH=YES ARCHS=arm64 build > "$evidence_dir/native-build.log" 2>&1 || {
    tail -120 "$evidence_dir/native-build.log"; exit 1;
  }
python3 - "$evidence_dir" <<'PY'
from pathlib import Path
import json,sys
p=Path(sys.argv[1])
app=p/'DerivedData/Build/Products/Debug-iphonesimulator/Incyclist.app'
assert app.exists()
(p/'native-build-record.json').write_text(json.dumps({
  'upstreamCommit':'1969e6442a9ae807b1f9ae0b9cd865400d7d6873',
  'nativeBuild':True,'signed':False,'hardwareTested':False,
  'trainerEffectVerified':False,'storeReady':False
},indent=2)+'\n')
PY
# Keep logs and a machine-readable result, not multi-gigabyte DerivedData artifacts.
rm -rf "$evidence_dir/DerivedData"
