#!/usr/bin/env python3
"""Apply the integration to the audited clean Incyclist commit; never guesses newer layout."""
from pathlib import Path
import hashlib
import plistlib
import re
import shutil
import subprocess
import sys

PIN = "1969e6442a9ae807b1f9ae0b9cd865400d7d6873"
HERE = Path(__file__).resolve().parent
KIT = HERE.parents[1]


def apply(target):
    target = target.resolve()
    head = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=target, text=True).strip()
    status = subprocess.check_output(["git", "status", "--porcelain"], cwd=target, text=True).strip()
    if head != PIN or status:
        raise SystemExit("Requires clean incyclist/mobile@" + PIN + "; review changes before adapting.")

    def key(name):
        return hashlib.sha256(("clickbridge/" + name).encode()).hexdigest()[:24].upper()

    def once(text, anchor, replacement):
        if text.count(anchor) != 1:
            raise SystemExit("Unexpected upstream structure: " + anchor[:80])
        return text.replace(anchor, replacement, 1)

    def phase_insert(text, phase, lines):
        pattern = r"(isa = " + phase + r";\s*buildActionMask = \d+;\s*files = \(\n)"
        text, count = re.subn(pattern, lambda m: m[1] + lines, text)
        if count != 1:
            raise SystemExit("Unexpected build phase count: " + phase)
        return text

    project = target / "ios/Incyclist.xcodeproj/project.pbxproj"
    pbx = project.read_text()
    builds, refs, source_entries, resource_entries, framework_entries, product_entries = [], [], [], [], [], []
    group_entries = []
    for name, kind, phase in [("ClickBridgeModule.swift", "sourcecode.swift", source_entries),
                              ("ClickBridgeModule.m", "sourcecode.c.objc", source_entries),
                              ("THIRD_PARTY_NOTICES.md", "text", resource_entries)]:
        file_id, build_id = key(name), key(name + ":build")
        refs.append(f'\t\t{file_id} = {{isa = PBXFileReference; lastKnownFileType = {kind}; path = ClickBridge/{name}; sourceTree = SOURCE_ROOT; }};\n')
        builds.append(f'\t\t{build_id} = {{isa = PBXBuildFile; fileRef = {file_id}; }};\n')
        phase.append(f'\t\t\t\t{build_id},\n'); group_entries.append(f'\t\t\t\t{file_id},\n')
    for name in ["ClickBridgeCore", "ClickBridgeBLE"]:
        build_id, product_id = key(name + ":build"), key(name)
        builds.append(f'\t\t{build_id} = {{isa = PBXBuildFile; productRef = {product_id}; }};\n')
        product_entries.append(f'\t\t{product_id} = {{isa = XCSwiftPackageProductDependency; package = {key("package")}; productName = {name}; }};\n')
        framework_entries.append(f'\t\t\t\t{build_id},\n')
    pbx = once(pbx, "/* End PBXBuildFile section */", "".join(builds) + "/* End PBXBuildFile section */")
    pbx = once(pbx, "/* End PBXFileReference section */", "".join(refs) + "/* End PBXFileReference section */")
    anchor = "13B07FAE1A68108700A75B9A /* Incyclist */ = {\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n"
    pbx = once(pbx, anchor, anchor + "".join(group_entries))
    pbx = phase_insert(pbx, "PBXSourcesBuildPhase", "".join(source_entries))
    pbx = phase_insert(pbx, "PBXResourcesBuildPhase", "".join(resource_entries))
    pbx = phase_insert(pbx, "PBXFrameworksBuildPhase", "".join(framework_entries))
    anchor = "packageProductDependencies = (\n"
    pbx = once(pbx, anchor, anchor + "".join(f'\t\t\t\t{key(n)},\n' for n in ["ClickBridgeCore", "ClickBridgeBLE"]))
    anchor = "packageReferences = (\n"
    pbx = once(pbx, anchor, anchor + f'\t\t\t\t{key("package")},\n')
    pbx = once(pbx, "/* End XCSwiftPackageProductDependency section */", "".join(product_entries) + "/* End XCSwiftPackageProductDependency section */")
    anchor = "/* Begin XCRemoteSwiftPackageReference section */"
    local = f'/* Begin XCLocalSwiftPackageReference section */\n\t\t{key("package")} = {{isa = XCLocalSwiftPackageReference; relativePath = "../clickbridge-kit"; }};\n/* End XCLocalSwiftPackageReference section */\n\n'
    pbx = once(pbx, anchor, local + anchor)
    pbx = re.sub(r"IPHONEOS_DEPLOYMENT_TARGET = [\d.]+;", "IPHONEOS_DEPLOYMENT_TARGET = 18.0;", pbx)

    appdelegate = target / "ios/Incyclist/AppDelegate.swift"
    app = once(appdelegate.read_text(), "        let delegate = ReactNativeDelegate()", "        _ = ClickBridgeHost.shared // Initialize CoreBluetooth restoration before React.\n        let delegate = ReactNativeDelegate()")
    page = target / "src/pages/RidePage/RidePage.tsx"
    source = page.read_text()
    source = "import { ClickBridgeControls } from '../../integrations/clickbridge/ClickBridgeControls';\n" + source
    source = once(source, "export const RidePage = ({ simulate = false }: RidePageProps) => {", "const RidePageContent = ({ simulate = false }: RidePageProps) => {")
    source += "\nexport const RidePage = ({ simulate = false }: RidePageProps) => (\n    <View style={{ flex: 1 }}>\n        <RidePageContent simulate={simulate} />\n        <ClickBridgeControls simulate={simulate} />\n    </View>\n);\n"
    podfile = target / "ios/Podfile"
    pods = once(podfile.read_text(), "min_ios_version_supported = '15.5'", "min_ios_version_supported = '18.0'")
    pods = re.sub(r"(min_ios_version_supported = '18.0')[ \t]+", r"\1", pods)
    infofile = target / "ios/Incyclist/Info.plist"
    info = plistlib.loads(infofile.read_bytes())
    modes = info.setdefault("UIBackgroundModes", [])
    if "bluetooth-central" not in modes: modes.append("bluetooth-central")
    info.setdefault("NSBluetoothAlwaysUsageDescription", "Incyclist verbindet Smarttrainer und ClickBridge-Schaltcontroller.")
    privacyfile = target / "ios/Incyclist/PrivacyInfo.xcprivacy"
    privacy = plistlib.loads(privacyfile.read_bytes())
    apis = privacy.setdefault("NSPrivacyAccessedAPITypes", [])
    userdefaults = next((x for x in apis if x.get("NSPrivacyAccessedAPIType") == "NSPrivacyAccessedAPICategoryUserDefaults"), None)
    if userdefaults is None:
        apis.append({"NSPrivacyAccessedAPIType": "NSPrivacyAccessedAPICategoryUserDefaults", "NSPrivacyAccessedAPITypeReasons": ["CA92.1"]})
    elif "CA92.1" not in userdefaults["NSPrivacyAccessedAPITypeReasons"]:
        userdefaults["NSPrivacyAccessedAPITypeReasons"].append("CA92.1")

    # Validate all textual anchors before mutating this clean checkout.
    destination = target / "clickbridge-kit"
    destination.mkdir()
    for name in ["Package.swift", "LICENSE", "THIRD_PARTY_NOTICES.md"]:
        shutil.copy2(KIT / name, destination / name)
    for name in ["Sources", "Tests"]:
        shutil.copytree(KIT / name, destination / name)
    native = target / "ios/ClickBridge"; native.mkdir()
    for name in ["ClickBridgeModule.swift", "ClickBridgeModule.m"]: shutil.copy2(HERE / name, native / name)
    shutil.copy2(KIT / "THIRD_PARTY_NOTICES.md", native / "THIRD_PARTY_NOTICES.md")
    js = target / "src/integrations/clickbridge"; js.mkdir(parents=True)
    for name in ["ClickBridgeControls.tsx", "shiftRouter.js", "shiftRouter.d.ts", "shiftRouter.test.cjs"]:
        shutil.copy2(HERE / name, js / name)
    project.write_text(pbx); appdelegate.write_text(app); page.write_text(source); podfile.write_text(pods)
    infofile.write_bytes(plistlib.dumps(info, sort_keys=False)); privacyfile.write_bytes(plistlib.dumps(privacy, sort_keys=False))
    print("Integrated source into", target)
    print("Native Incyclist build and all real hardware acceptance tests remain required.")


if __name__ == "__main__":
    if len(sys.argv) != 2: raise SystemExit("Usage: install.py /absolute/path/to/clean/incyclist-mobile")
    apply(Path(sys.argv[1]))
