#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
output_dir="$project_dir/build"
mkdir -p "$output_dir"
xcodebuild -version
xcrun swift "$project_dir/scripts/render-icon.swift" "$project_dir/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
xcrun swiftc -O "$project_dir/Sources/CSS.swift" "$project_dir/Sources/Diagnostics.swift" "$project_dir/Sources/RuntimeAudit.swift" "$project_dir/Tests/main.swift" -o "$output_dir/css-tests"
"$output_dir/css-tests" --json "$output_dir/diagnostics-report.json" | tee "$output_dir/test-results.txt"
xcodebuild -project "$project_dir/LoRaLab.xcodeproj" -scheme LoRaLab \
  -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' \
  -derivedDataPath "$output_dir/DerivedData" CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO build | tee "$output_dir/xcodebuild.log"
app="$output_dir/DerivedData/Build/Products/Release-iphoneos/LoRaLab.app"
test -f "$app/LoRaLab"
lipo "$app/LoRaLab" -verify_arch arm64
package_dir="$(mktemp -d "$output_dir/package.XXXXXX")"
trap 'rm -rf "$package_dir"' EXIT
mkdir -p "$package_dir/Payload"
ditto "$app" "$package_dir/Payload/LoRaLab.app"
(cd "$package_dir" && /usr/bin/zip -qry "$output_dir/LoRaLab-unsigned.ipa" Payload)
shasum -a 256 "$output_dir/LoRaLab-unsigned.ipa" > "$output_dir/SHA256SUMS.txt"
python3 - "$output_dir/LoRaLab-unsigned.ipa" <<'PY'
import plistlib,sys,zipfile
with zipfile.ZipFile(sys.argv[1]) as z:
    assert z.testzip() is None
    p=plistlib.loads(z.read('Payload/LoRaLab.app/Info.plist'))
    assert p['CFBundleIdentifier']=='de.p1337.LoRaLab'
    assert z.read('Payload/LoRaLab.app/LoRaLab')[:4] == bytes.fromhex('cffaedfe')
    print('Validated arm64 device IPA:',p['CFBundleDisplayName'])
PY
printf '%s\n' 'Unsigned device IPA. Re-sign with AltStore Classic/AltServer before installation.'
