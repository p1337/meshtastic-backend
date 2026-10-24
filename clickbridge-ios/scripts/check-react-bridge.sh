#!/bin/bash
# Compile the actual Swift/ObjC glue against the pinned React Native headers.
# This is a narrow ABI/typecheck gate, not a replacement for the full native build.
set -euo pipefail
kit_root="$(cd "$(dirname "$0")/.." && pwd)"
upstream_root="${1:?Supply the audited upstream checkout}"
check_dir="$kit_root/build/react-bridge-check"
mkdir -p "$check_dir/headers/React"
python3 - "$upstream_root" "$check_dir" <<'PY'
from pathlib import Path
import base64,hashlib,io,json,re,shutil,sys,tarfile,urllib.request
root,out=map(Path,sys.argv[1:])
shutil.rmtree(out/'headers',ignore_errors=True)
(out/'headers/React').mkdir(parents=True)
lock=json.loads((root/'package-lock.json').read_text())
entry=lock['packages']['node_modules/react-native']
with urllib.request.urlopen(entry['resolved'],timeout=30) as response: raw=response.read()
expected=entry['integrity'].removeprefix('sha512-')
assert base64.b64encode(hashlib.sha512(raw).digest()).decode()==expected
with tarfile.open(fileobj=io.BytesIO(raw),mode='r:gz') as archive:
    headers={}
    for member in archive.getmembers():
        if member.isfile() and member.name.endswith('.h'):
            headers[member.name]=archive.extractfile(member).read()
    byname={Path(name).name: data for name,data in headers.items()}
    for name,data in byname.items():
        (out/'headers/React'/name).write_bytes(data)
    # Keep generic filenames (e.g. renderer/graphics/float.h) out of the root
    # include path: flattening them there shadows Apple's standard C headers.
    # CocoaPods normally supplies these header namespaces (e.g. RCTDeprecation).
    # Recreate their real, integrity-checked headers without inventing declarations.
    for data in headers.values():
        for spec in re.findall(rb'#(?:import|include)\s*[<"]([A-Za-z0-9_.\-/]+/[^>"\s]+\.h)[>"]',data):
            rel=Path(spec.decode())
            if rel.is_absolute() or '..' in rel.parts: continue
            exact=next((v for k,v in headers.items() if k.endswith('/'+rel.as_posix())),None)
            content=exact if exact is not None else byname.get(rel.name)
            if content is not None:
                destination=out/'headers'/rel
                destination.parent.mkdir(parents=True,exist_ok=True)
                destination.write_bytes(content)
(out/'headers/module.modulemap').write_text('module React { header "React/RCTEventEmitter.h" header "React/RCTUtils.h" export * }\n')
(out/'header-source.json').write_text(json.dumps({'reactNative':entry['version'],'npmIntegrityVerified':True},indent=2)+'\n')
PY
sdk_path="$(xcrun --sdk iphonesimulator --show-sdk-path)"
xcrun swift build --package-path "$kit_root" --scratch-path "$check_dir/spm" \
  --sdk "$sdk_path" --triple arm64-apple-ios18.0-simulator --target ClickBridgeBLE \
  > "$check_dir/package-build.log" 2>&1 || { tail -70 "$check_dir/package-build.log"; exit 1; }
module_file="$(find "$check_dir/spm" -name ClickBridgeCore.swiftmodule -type f | head -1)"
test -n "$module_file"
module_dir="$(dirname "$module_file")"
xcrun swiftc -typecheck -swift-version 5 -target arm64-apple-ios18.0-simulator -sdk "$sdk_path" \
  -I "$module_dir" -I "$check_dir/headers" -Xcc -I"$check_dir/headers" -Xcc -DRCT_NEW_ARCH_ENABLED=1 \
  "$kit_root/integrations/incyclist/ClickBridgeModule.swift" > "$check_dir/swift-glue.log" 2>&1 || {
    cat "$check_dir/swift-glue.log"; exit 1;
  }
xcrun clang -fsyntax-only -fmodules -x objective-c -target arm64-apple-ios18.0-simulator \
  -isysroot "$sdk_path" -I "$check_dir/headers" -DRCT_NEW_ARCH_ENABLED=1 \
  "$kit_root/integrations/incyclist/ClickBridgeModule.m" > "$check_dir/objc-glue.log" 2>&1 || {
    cat "$check_dir/objc-glue.log"; exit 1;
  }
printf '%s\n' 'Actual Swift/ObjC glue compiled against integrity-checked React Native headers. Full native linking and hardware tests remain separate.'
