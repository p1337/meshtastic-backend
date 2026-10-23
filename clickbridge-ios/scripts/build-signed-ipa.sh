#!/bin/bash
# Build, Apple-sign, export and independently verify the ClickBridge Ad Hoc IPA.
set -euo pipefail
umask 077
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
output_dir="$project_dir/build/signed"
mkdir -p "$output_dir"

for name in IOS_DISTRIBUTION_P12_BASE64 IOS_P12_PASSWORD CLICKBRIDGE_ADHOC_PROFILE_BASE64; do
  if [ -z "${!name:-}" ]; then
    printf '::error::Missing signing value %s in apple-signing.\n' "$name"
    exit 1
  fi
done

signing_dir="$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/clickbridge-signing.XXXXXX")"
keychain_path="$signing_dir/signing.keychain-db"
installed_profile=""
cleanup() {
  security delete-keychain "$keychain_path" >/dev/null 2>&1 || true
  if [ -n "$installed_profile" ]; then rm -f "$installed_profile"; fi
  rm -rf "$signing_dir"
}
trap cleanup EXIT
export CLICKBRIDGE_SIGNING_DIR="$signing_dir"
export CLICKBRIDGE_SIGNED_OUTPUT="$output_dir"

python3 - <<'PY'
import base64, os
from pathlib import Path
p=Path(os.environ['CLICKBRIDGE_SIGNING_DIR'])
for env,name in [('IOS_DISTRIBUTION_P12_BASE64','distribution.p12'),
                 ('CLICKBRIDGE_ADHOC_PROFILE_BASE64','profile.mobileprovision')]:
    value=base64.b64decode(''.join(os.environ[env].split()),validate=True)
    if not value: raise ValueError('Empty signing input')
    (p/name).write_bytes(value)
PY
security cms -D -i "$signing_dir/profile.mobileprovision" > "$signing_dir/profile.plist"
python3 - <<'PY'
import datetime, hashlib, os, plistlib, re
from pathlib import Path
p=Path(os.environ['CLICKBRIDGE_SIGNING_DIR']); v=plistlib.loads((p/'profile.plist').read_bytes())
bundle='de.p1337.ClickBridge'; team=v['TeamIdentifier'][0]; uuid=v['UUID']; e=v['Entitlements']
assert re.fullmatch('[A-Z0-9]{10}',team),'Invalid Team ID'
assert re.fullmatch('[A-Fa-f0-9-]{36}',uuid),'Invalid profile UUID'
prefix=v['ApplicationIdentifierPrefix'][0]
app_id=e.get('application-identifier','')
assert app_id==prefix+'.'+bundle or (app_id.endswith('.*') and (prefix+'.'+bundle).startswith(app_id[:-1])), 'Profile App ID must match '+bundle
assert e.get('com.apple.developer.team-identifier')==team,'Profile Team ID mismatch'
assert not e.get('get-task-allow',False),'Use Ad Hoc distribution, not a development profile'
assert v.get('ProvisionedDevices') and not v.get('ProvisionsAllDevices',False),'Ad Hoc profile with registered iPhone required'
assert v['ExpirationDate']>datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None),'Expired profile'
certificates=v.get('DeveloperCertificates',[])
assert certificates,'Profile has no developer certificate'
fingerprints=[hashlib.sha1(c).hexdigest().upper() for c in certificates]
(p/'team').write_text(team); (p/'uuid').write_text(uuid); (p/'fingerprints').write_text('\n'.join(fingerprints))
options={'method':'release-testing','signingStyle':'manual','teamID':team,
         'provisioningProfiles':{bundle:uuid},'stripSwiftSymbols':True}
(p/'ExportOptions.plist').write_bytes(plistlib.dumps(options))
print('Validated ClickBridge Ad Hoc profile; registered device count:',len(v['ProvisionedDevices']))
PY

keychain_password="$(openssl rand -hex 24)"
security create-keychain -p "$keychain_password" "$keychain_path"
security set-keychain-settings -lut 3600 "$keychain_path"
security unlock-keychain -p "$keychain_password" "$keychain_path"
if ! security import "$signing_dir/distribution.p12" -P "$IOS_P12_PASSWORD" -k "$keychain_path" \
  -T /usr/bin/codesign -T /usr/bin/security > "$signing_dir/import.log" 2>&1; then
  openssl3=""
  for candidate in /opt/homebrew/opt/openssl@3/bin/openssl /usr/local/opt/openssl@3/bin/openssl "$(command -v openssl)"; do
    if [ -x "$candidate" ] && "$candidate" version | grep -q '^OpenSSL 3\.'; then openssl3="$candidate"; break; fi
  done
  test -n "$openssl3" || { printf '%s\n' '::error::P12 import failed and OpenSSL 3 is unavailable.'; exit 1; }
  "$openssl3" pkcs12 -in "$signing_dir/distribution.p12" -passin env:IOS_P12_PASSWORD \
    -passout env:IOS_P12_PASSWORD -out "$signing_dir/identity-encrypted.pem" >/dev/null 2>&1 || {
      printf '%s\n' '::error::P12 password or file is invalid.'; exit 1;
    }
  "$openssl3" pkcs12 -export -legacy -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1 \
    -in "$signing_dir/identity-encrypted.pem" -out "$signing_dir/compatible.p12" \
    -passin env:IOS_P12_PASSWORD -passout env:IOS_P12_PASSWORD >/dev/null 2>&1
  security import "$signing_dir/compatible.p12" -P "$IOS_P12_PASSWORD" -k "$keychain_path" \
    -T /usr/bin/codesign -T /usr/bin/security >/dev/null
fi
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$keychain_password" "$keychain_path" >/dev/null
security list-keychains -d user -s "$keychain_path" /Library/Keychains/System.keychain
security find-identity -v -p codesigning "$keychain_path" > "$signing_dir/identities.txt"
identity=""
while IFS= read -r fingerprint; do
  if grep -q "$fingerprint.*Apple Distribution" "$signing_dir/identities.txt"; then identity="$fingerprint"; break; fi
done < "$signing_dir/fingerprints"
test -n "$identity" || { printf '%s\n' '::error::P12 does not contain a distribution identity allowed by the profile.'; exit 1; }

team_id="$(cat "$signing_dir/team")"; profile_uuid="$(cat "$signing_dir/uuid")"
profile_dir="$HOME/Library/MobileDevice/Provisioning Profiles"; mkdir -p "$profile_dir"
installed_profile="$profile_dir/$profile_uuid.mobileprovision"; cp "$signing_dir/profile.mobileprovision" "$installed_profile"

cd "$project_dir"
python3 scripts/generate_project.py
xcodebuild -project ClickBridge.xcodeproj -scheme ClickBridge -configuration Release \
  -destination 'generic/platform=iOS' -archivePath "$output_dir/ClickBridge.xcarchive" \
  CURRENT_PROJECT_VERSION="${GITHUB_RUN_NUMBER:-1}" CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="$team_id" \
  CODE_SIGN_IDENTITY="$identity" PROVISIONING_PROFILE_SPECIFIER="$profile_uuid" archive \
  > "$signing_dir/archive.log" 2>&1 || {
    printf '%s\n' '::error::ClickBridge archive/signing failed.'
    grep -E 'error:|ARCHIVE FAILED' "$signing_dir/archive.log" | tail -30 || true; exit 1;
  }
xcodebuild -exportArchive -archivePath "$output_dir/ClickBridge.xcarchive" -exportPath "$output_dir/export" \
  -exportOptionsPlist "$signing_dir/ExportOptions.plist" > "$signing_dir/export.log" 2>&1 || {
    printf '%s\n' '::error::ClickBridge signed IPA export failed.'
    grep -E 'error:|EXPORT FAILED' "$signing_dir/export.log" | tail -30 || true; exit 1;
  }
cp "$output_dir/export/ClickBridge.ipa" "$output_dir/ClickBridge-Apple-signed.ipa"

verify_dir="$signing_dir/verify"; mkdir "$verify_dir"
ditto -x -k "$output_dir/ClickBridge-Apple-signed.ipa" "$verify_dir"
app="$verify_dir/Payload/ClickBridge.app"
codesign --verify --deep --strict "$app"
codesign -dvv "$app" > "$signing_dir/signature.txt" 2>&1
grep -q 'Authority=Apple Distribution:' "$signing_dir/signature.txt"
grep -q "TeamIdentifier=$team_id" "$signing_dir/signature.txt"
lipo "$app/ClickBridge" -verify_arch arm64
security cms -D -i "$app/embedded.mobileprovision" > "$signing_dir/embedded.plist"
python3 - <<'PY'
import hashlib, json, os, plistlib, struct
from pathlib import Path
p=Path(os.environ['CLICKBRIDGE_SIGNING_DIR']); out=Path(os.environ['CLICKBRIDGE_SIGNED_OUTPUT'])
profile=plistlib.loads((p/'embedded.plist').read_bytes()); app=p/'verify/Payload/ClickBridge.app'
info=plistlib.loads((app/'Info.plist').read_bytes()); binary=(app/'ClickBridge').read_bytes()
assert profile['UUID']==(p/'uuid').read_text(); assert profile['TeamIdentifier'][0]==(p/'team').read_text()
assert info['CFBundleIdentifier']=='de.p1337.ClickBridge'
assert struct.unpack_from('<II',binary)==(0xfeedfacf,0x100000c),'Expected arm64 device Mach-O'
ipa=out/'ClickBridge-Apple-signed.ipa'
record={'bundle_id':info['CFBundleIdentifier'],'apple_distribution_signature_verified':True,
        'provisioning_profile_matches':True,'profile_expires_utc':profile['ExpirationDate'].isoformat()+'Z',
        'registered_device_count':len(profile['ProvisionedDevices']),'ipa_sha256':hashlib.sha256(ipa.read_bytes()).hexdigest(),
        'hardware_tested':False,'incyclist_integration_verified':False}
(out/'signature-verification.json').write_text(json.dumps(record,indent=2)+'\n')
PY
(cd "$output_dir" && shasum -a 256 ClickBridge-Apple-signed.ipa > SHA256SUMS.txt)
printf '%s\n' 'Created and verified ClickBridge-Apple-signed.ipa.'
