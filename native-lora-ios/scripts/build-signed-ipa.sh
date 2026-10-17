#!/bin/bash
# Real Apple Distribution signing. Requires an Apple-issued Ad Hoc profile.
set -euo pipefail
umask 077
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
output_dir="$project_dir/build-signed"
mkdir -p "$output_dir"
for name in IOS_DISTRIBUTION_P12_BASE64 IOS_P12_PASSWORD IOS_ADHOC_PROFILE_BASE64; do
  if [ -z "${!name:-}" ]; then
    printf '::error::Missing GitHub Actions secret: %s. See native-lora-ios/SIGNING.md\n' "$name"
    exit 1
  fi
done
signing_dir="$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/loralab-signing.XXXXXX")"
keychain_path="$signing_dir/signing.keychain-db"
installed_profile=""
cleanup() {
  security delete-keychain "$keychain_path" >/dev/null 2>&1 || true
  if [ -n "$installed_profile" ]; then rm -f "$installed_profile"; fi
  rm -rf "$signing_dir"
}
trap cleanup EXIT
export SIGNING_DIR="$signing_dir"
export SIGNED_OUTPUT_DIR="$output_dir"
python3 - <<'PY'
import base64,os,pathlib
p=pathlib.Path(os.environ['SIGNING_DIR'])
for env,name in [('IOS_DISTRIBUTION_P12_BASE64','distribution.p12'),('IOS_ADHOC_PROFILE_BASE64','profile.mobileprovision')]:
    data=base64.b64decode(''.join(os.environ[env].split()),validate=True)
    if not data: raise ValueError('Empty signing input')
    (p/name).write_bytes(data)
PY
# Decode locally. Do not print the provisioning profile or device identifiers.
security cms -D -i "$signing_dir/profile.mobileprovision" > "$signing_dir/profile.plist"
python3 - <<'PY'
import datetime,hashlib,os,pathlib,plistlib,re
p=pathlib.Path(os.environ['SIGNING_DIR']);v=plistlib.loads((p/'profile.plist').read_bytes())
bundle='de.p1337.LoRaLab';team=v['TeamIdentifier'][0];uuid=v['UUID'];e=v['Entitlements']
assert re.fullmatch('[A-Z0-9]{10}',team),'Invalid Team ID'
assert re.fullmatch('[A-Fa-f0-9-]{36}',uuid),'Invalid profile UUID'
prefix=v['ApplicationIdentifierPrefix'][0]
assert re.fullmatch('[A-Z0-9]{10}',prefix),'Invalid App ID prefix'
assert e.get('com.apple.developer.team-identifier')==team,'Profile Team ID mismatch'
assert e.get('application-identifier') == prefix+'.'+bundle,'Profile App ID must match '+bundle
assert not e.get('get-task-allow',False),'Use Ad Hoc distribution, not a development profile'
assert v.get('ProvisionedDevices') and not v.get('ProvisionsAllDevices',False),'Ad Hoc profile with registered iPhone required'
assert v['ExpirationDate'] > datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None),'Expired profile'
assert len(v.get('DeveloperCertificates',[]))==1,'Expected exactly one distribution certificate'
fingerprint=hashlib.sha1(v['DeveloperCertificates'][0]).hexdigest().upper()
(p/'team').write_text(team);(p/'uuid').write_text(uuid);(p/'identity').write_text(fingerprint)
options={'method':'release-testing','signingStyle':'manual','teamID':team,'signingCertificate':fingerprint,
         'provisioningProfiles':{bundle:uuid},'stripSwiftSymbols':True}
(p/'ExportOptions.plist').write_bytes(plistlib.dumps(options))
print('Validated Ad Hoc profile for LoRaLab; registered device count:',len(v['ProvisionedDevices']))
PY
team_id="$(cat "$signing_dir/team")"
profile_uuid="$(cat "$signing_dir/uuid")"
identity="$(cat "$signing_dir/identity")"
keychain_password="$(openssl rand -hex 24)"
security create-keychain -p "$keychain_password" "$keychain_path"
security set-keychain-settings -lut 3600 "$keychain_path"
security unlock-keychain -p "$keychain_password" "$keychain_path"
if ! security import "$signing_dir/distribution.p12" -P "$IOS_P12_PASSWORD" \
  -k "$keychain_path" -T /usr/bin/codesign -T /usr/bin/security \
  > "$signing_dir/import.log" 2>&1; then
  # Apple Security may reject the PBES2/AES defaults used by modern PKCS12
  # exporters. Repackage the SAME key and certificate using compatible PBE.
  # Both the intermediate PEM and the replacement P12 stay encrypted.
  openssl3=""
  for candidate in /opt/homebrew/opt/openssl@3/bin/openssl /usr/local/opt/openssl@3/bin/openssl "$(command -v openssl)"; do
    if [ -x "$candidate" ] && "$candidate" version | grep -q '^OpenSSL 3\.'; then
      openssl3="$candidate"
      break
    fi
  done
  if [ -z "$openssl3" ]; then
    printf '%s\n' '::error::Apple PKCS12 import failed; OpenSSL 3 is required for compatibility conversion.'
    exit 1
  fi
  if ! "$openssl3" pkcs12 -in "$signing_dir/distribution.p12" \
    -passin env:IOS_P12_PASSWORD -passout env:IOS_P12_PASSWORD \
    -out "$signing_dir/identity-encrypted.pem" > "$signing_dir/convert.log" 2>&1; then
    printf '%s\n' '::error::OpenSSL also could not open the P12. Check that IOS_P12_PASSWORD matches the uploaded P12; no password check was bypassed.'
    exit 1
  fi
  "$openssl3" pkcs12 -export -legacy -keypbe PBE-SHA1-3DES \
    -certpbe PBE-SHA1-3DES -macalg sha1 \
    -in "$signing_dir/identity-encrypted.pem" -out "$signing_dir/compatible.p12" \
    -passin env:IOS_P12_PASSWORD -passout env:IOS_P12_PASSWORD \
    > "$signing_dir/repack.log" 2>&1
  security import "$signing_dir/compatible.p12" -P "$IOS_P12_PASSWORD" \
    -k "$keychain_path" -T /usr/bin/codesign -T /usr/bin/security >/dev/null
  rm -f "$signing_dir/identity-encrypted.pem" "$signing_dir/compatible.p12"
  printf '%s\n' 'Imported unchanged Apple identity after PKCS12 compatibility conversion.'
fi
security set-key-partition-list -S apple-tool:,apple:,codesign: -s \
  -k "$keychain_password" "$keychain_path" >/dev/null
security list-keychains -d user -s "$keychain_path" /Library/Keychains/System.keychain
security find-identity -v -p codesigning "$keychain_path" > "$signing_dir/identities.txt"
if ! grep -q "$identity.*Apple Distribution" "$signing_dir/identities.txt"; then
  printf '%s\n' '::error::P12 must contain the valid Apple Distribution private key and certificate selected in the Ad Hoc profile.'
  exit 1
fi
profile_dir="$HOME/Library/MobileDevice/Provisioning Profiles"
mkdir -p "$profile_dir"
installed_profile="$profile_dir/$profile_uuid.mobileprovision"
cp "$signing_dir/profile.mobileprovision" "$installed_profile"
xcodebuild -version
xcrun swiftc "$project_dir/Sources/CSS.swift" "$project_dir/Tests/main.swift" -o "$output_dir/css-tests"
"$output_dir/css-tests" | tee "$output_dir/test-results.txt"
xcodebuild -project "$project_dir/LoRaLab.xcodeproj" -scheme LoRaLab \
  -configuration Release -destination 'generic/platform=iOS' \
  -archivePath "$output_dir/LoRaLab.xcarchive" \
  CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="$team_id" \
  CODE_SIGN_IDENTITY="$identity" PROVISIONING_PROFILE_SPECIFIER="$profile_uuid" \
  archive > "$signing_dir/archive.log" 2>&1 || {
    printf '%s\n' '::error::Xcode archive/signing failed. No unsigned fallback produced.'
    grep -E 'error:|ARCHIVE FAILED' "$signing_dir/archive.log" | tail -20 || true
    exit 1
  }
xcodebuild -exportArchive -archivePath "$output_dir/LoRaLab.xcarchive" \
  -exportPath "$output_dir/export" -exportOptionsPlist "$signing_dir/ExportOptions.plist" \
  > "$signing_dir/export.log" 2>&1 || {
    printf '%s\n' '::error::Xcode signed IPA export failed. No unsigned fallback produced.'
    grep -E 'error:|EXPORT FAILED' "$signing_dir/export.log" | tail -20 || true
    exit 1
  }
cp "$output_dir/export/LoRaLab.ipa" "$output_dir/LoRaLab-Apple-signed.ipa"
# Verify both a real Apple signing authority and the certificate/profile binding.
verify_dir="$signing_dir/verify"
mkdir "$verify_dir"
ditto -x -k "$output_dir/LoRaLab-Apple-signed.ipa" "$verify_dir"
app="$verify_dir/Payload/LoRaLab.app"
codesign --verify --deep --strict "$app"
codesign -dvv "$app" > "$signing_dir/signature.txt" 2>&1
grep -q 'Authority=Apple Distribution:' "$signing_dir/signature.txt"
grep -q "TeamIdentifier=$team_id" "$signing_dir/signature.txt"
lipo "$app/LoRaLab" -verify_arch arm64
security cms -D -i "$app/embedded.mobileprovision" > "$signing_dir/embedded.plist"
python3 - <<'PY'
import datetime,hashlib,json,os,pathlib,plistlib,struct
p=pathlib.Path(os.environ['SIGNING_DIR']);v=plistlib.loads((p/'embedded.plist').read_bytes())
assert v['UUID']==(p/'uuid').read_text(),'Export changed provisioning profile'
assert v['TeamIdentifier'][0]==(p/'team').read_text()
a=p/'verify/Payload/LoRaLab.app';info=plistlib.loads((a/'Info.plist').read_bytes());binary=(a/'LoRaLab').read_bytes()
assert info['CFBundleIdentifier']=='de.p1337.LoRaLab'
assert struct.unpack_from('<II',binary)==(0xfeedfacf,0x100000c),'Expected arm64 device Mach-O'
header=struct.unpack_from('<IIIIIIII',binary);pos=32;signed=False;ios=False
for _ in range(header[4]):
    cmd,size=struct.unpack_from('<II',binary,pos);assert size>=8
    signed|=cmd==0x1d
    if cmd==0x32: ios=struct.unpack_from('<I',binary,pos+8)[0]==2
    pos+=size
assert signed and ios,'Missing device signature or incorrect platform'
out=pathlib.Path(os.environ['SIGNED_OUTPUT_DIR']);ipa=out/'LoRaLab-Apple-signed.ipa'
record={'bundle_id':info['CFBundleIdentifier'],'cpu':'arm64','apple_distribution_signature_verified':True,
        'provisioning_profile_matches':True,'profile_expires_utc':v['ExpirationDate'].isoformat()+'Z',
        'registered_device_count':len(v['ProvisionedDevices']),'ipa_sha256':hashlib.sha256(ipa.read_bytes()).hexdigest(),
        'live_lora_reception':False,'on_device_execution_verified':False}
(out/'signature-verification.json').write_text(json.dumps(record,indent=2)+'\n')
print('Verified Apple Distribution signature, Ad Hoc profile and arm64 iOS device binary.')
PY
(cd "$output_dir" && shasum -a 256 LoRaLab-Apple-signed.ipa > SHA256SUMS.txt)
printf '%s\n' 'Created LoRaLab-Apple-signed.ipa. No AltStore re-signing is required.'
