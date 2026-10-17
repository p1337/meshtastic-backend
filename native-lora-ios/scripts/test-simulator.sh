#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
output_dir="$project_dir/build-simulator"
mkdir -p "$output_dir"
xcrun simctl list devices available -j > "$output_dir/devices.json"
sdk_version="$(xcrun --sdk iphonesimulator --show-sdk-version)"
device_id="$(python3 - "$output_dir/devices.json" "$sdk_version" <<'PY'
import json,sys
v=json.load(open(sys.argv[1]))
preferred='iOS-'+sys.argv[2].replace('.', '-')
runtimes=sorted(v['devices'].items(),key=lambda item: preferred not in item[0])
for runtime,devices in runtimes:
    if 'iOS' not in runtime: continue
    for d in devices:
        if d.get('isAvailable') and d['name'].startswith('iPhone'):
            print('Simulator runtime: '+runtime,file=sys.stderr)
            print(d['udid']);sys.exit(0)
raise SystemExit('No available iPhone simulator runtime on runner')
PY
)"
cleanup() { xcrun simctl shutdown "$device_id" >/dev/null 2>&1 || true; }
trap cleanup EXIT
xcrun swift "$project_dir/scripts/render-icon.swift" "$project_dir/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
xcodebuild -project "$project_dir/LoRaLab.xcodeproj" -scheme LoRaLab \
  -configuration Debug -sdk iphonesimulator -destination "id=$device_id" \
  -derivedDataPath "$output_dir/DerivedData" CURRENT_PROJECT_VERSION="${GITHUB_RUN_NUMBER:-1}" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build > "$output_dir/build.log" 2>&1 || {
    grep -E 'error:|BUILD FAILED' "$output_dir/build.log" | tail -30 || true
    exit 1
  }
xcrun simctl boot "$device_id" 2>/dev/null || true
xcrun simctl bootstatus "$device_id" -b
app="$output_dir/DerivedData/Build/Products/Debug-iphonesimulator/LoRaLab.app"
xcrun simctl install "$device_id" "$app"
xcrun simctl launch "$device_id" de.p1337.LoRaLab
container="$(xcrun simctl get_app_container "$device_id" de.p1337.LoRaLab data)"
for attempt in $(seq 1 45); do
  if [ -s "$container/Documents/LoRaLab-Latest.json" ]; then break; fi
  sleep 2
done
test -s "$container/Documents/LoRaLab-Latest.json"
cp "$container/Documents/LoRaLab-Latest.json" "$output_dir/simulator-report.json"
python3 - "$output_dir/simulator-report.json" <<'PY'
import json,sys
v=json.load(open(sys.argv[1]));r=v['suite']
assert v['state']=='completed'
assert r['environment']['simulator'] is True
assert r['environment']['appVersion']=='0.2.0'
assert not r['liveRF'] and not r['packetDecoder']
assert len(r['noise'])==30
assert sum(c['cases'] for c in r['checks'])>=700
assert not [c for c in r['checks'] if c['status']=='failed'],r['checks']
print('PASS: native simulator app installed, launched and automatically produced a valid report with 30 AWGN points.')
PY
xcrun simctl io "$device_id" screenshot "$output_dir/simulator-tests.png"
cp "$project_dir/Assets.xcassets/AppIcon.appiconset/AppIcon.png" "$output_dir/AppIcon.png"
