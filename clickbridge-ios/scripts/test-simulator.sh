#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/simulator
python3 scripts/generate_project.py
xcodebuild -project ClickBridge.xcodeproj -scheme ClickBridge -configuration Debug \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO build > build/simulator/build.log 2>&1 || {
    tail -100 build/simulator/build.log; exit 1;
  }
simulator_id="$(xcrun simctl list devices available -j | python3 -c 'import sys,json; d=json.load(sys.stdin); print(next(x["udid"] for runtime,devices in d["devices"].items() if "iOS" in runtime for x in devices if "iPhone" in x["name"]))')"
xcrun simctl boot "$simulator_id" 2>/dev/null || true
xcrun simctl bootstatus "$simulator_id" -b
xcrun simctl install "$simulator_id" build/DerivedData/Build/Products/Debug-iphonesimulator/ClickBridge.app
xcrun simctl launch "$simulator_id" de.p1337.ClickBridge --clickbridge-smoke
container="$(xcrun simctl get_app_container "$simulator_id" de.p1337.ClickBridge data)"
for attempt in $(seq 1 20); do
  if [ -f "$container/Documents/ClickBridge-Smoke.json" ]; then break; fi
  sleep 1
done
cp "$container/Documents/ClickBridge-Smoke.json" build/simulator/ClickBridge-Smoke.json
python3 - <<'PY'
import json
from pathlib import Path
r=json.loads(Path('build/simulator/ClickBridge-Smoke.json').read_text())
assert r['integrationAvailable'] is False
assert r['hardwareTested'] is False and r['trainerCommandsSent'] == 0
assert r['gearCount'] == 24 and r['liveGear'] is None
print('Actual simulator app launch observed; no Bluetooth hardware or shifting tested.')
PY
# Allow SwiftUI to finish its first layout; no hardware behavior is simulated.
sleep 2
xcrun simctl io "$simulator_id" screenshot build/simulator/ClickBridge.png
