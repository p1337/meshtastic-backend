#!/usr/bin/env python3
"""Deterministic Xcode project with two local Swift Package products. No dependencies."""
from pathlib import Path
import hashlib
import json

ROOT = Path(__file__).resolve().parents[1]
objects = {}


def identifier(name):
    return hashlib.sha256(name.encode()).hexdigest()[:24].upper()


def obj(object_key, isa, **values):
    key = identifier(object_key)
    objects[key] = {"isa": isa, **values}
    return key


def encode(value, level=0):
    if isinstance(value, dict):
        return "{\n" + "".join("\t" * (level + 1) + json.dumps(str(k)) + " = " + encode(v, level + 1) + ";\n" for k, v in value.items()) + "\t" * level + "}"
    if isinstance(value, list):
        return "(\n" + "".join("\t" * (level + 1) + encode(v, level + 1) + ",\n" for v in value) + "\t" * level + ")"
    return json.dumps(str(value))


sources, resources, children = [], [], []
for path in sorted((ROOT / "App").glob("*.swift")):
    rel = path.relative_to(ROOT).as_posix()
    ref = obj(rel, "PBXFileReference", lastKnownFileType="sourcecode.swift", path=rel, sourceTree="<group>")
    children.append(ref)
    sources.append(obj(rel + ":build", "PBXBuildFile", fileRef=ref))
for path, kind in [("Resources/Assets.xcassets", "folder.assetcatalog"), ("Resources/PrivacyInfo.xcprivacy", "text.xml")]:
    ref = obj(path, "PBXFileReference", lastKnownFileType=kind, path=path, sourceTree="<group>")
    children.append(ref)
    resources.append(obj(path + ":build", "PBXBuildFile", fileRef=ref))

package = obj("package", "XCLocalSwiftPackageReference", relativePath=".")
product_dependencies, frameworks = [], []
for name in ["ClickBridgeCore", "ClickBridgeBLE"]:
    product = obj(name, "XCSwiftPackageProductDependency", package=package, productName=name)
    product_dependencies.append(product)
    frameworks.append(obj(name + ":build", "PBXBuildFile", productRef=product))
app = obj("app", "PBXFileReference", explicitFileType="wrapper.application", includeInIndex=0, path="ClickBridge.app", sourceTree="BUILT_PRODUCTS_DIR")
products = obj("products", "PBXGroup", children=[app], name="Products", sourceTree="<group>")
group = obj("main-group", "PBXGroup", children=children + [products], sourceTree="<group>")
source_phase = obj("sources", "PBXSourcesBuildPhase", buildActionMask=2147483647, files=sources, runOnlyForDeploymentPostprocessing=0)
resource_phase = obj("resources", "PBXResourcesBuildPhase", buildActionMask=2147483647, files=resources, runOnlyForDeploymentPostprocessing=0)
framework_phase = obj("frameworks", "PBXFrameworksBuildPhase", buildActionMask=2147483647, files=frameworks, runOnlyForDeploymentPostprocessing=0)

project_configs, target_configs = [], []
for name in ["Debug", "Release"]:
    project_configs.append(obj("project:" + name, "XCBuildConfiguration", name=name, buildSettings={
        "SDKROOT": "iphoneos", "IPHONEOS_DEPLOYMENT_TARGET": "18.0", "SWIFT_VERSION": "5.0",
        "CLANG_ENABLE_MODULES": "YES", "ENABLE_USER_SCRIPT_SANDBOXING": "YES",
        "DEBUG_INFORMATION_FORMAT": "dwarf" if name == "Debug" else "dwarf-with-dsym",
        "SWIFT_OPTIMIZATION_LEVEL": "-Onone" if name == "Debug" else "-O"
    }))
    target_configs.append(obj("target:" + name, "XCBuildConfiguration", name=name, buildSettings={
        "PRODUCT_BUNDLE_IDENTIFIER": "de.p1337.ClickBridge", "PRODUCT_NAME": "$(TARGET_NAME)",
        "INFOPLIST_FILE": "Resources/Info.plist", "GENERATE_INFOPLIST_FILE": "NO",
        "CODE_SIGN_STYLE": "Automatic", "TARGETED_DEVICE_FAMILY": "1,2",
        "MARKETING_VERSION": "0.1.0", "CURRENT_PROJECT_VERSION": "1",
        "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon", "SWIFT_EMIT_LOC_STRINGS": "YES",
        "LD_RUNPATH_SEARCH_PATHS": "$(inherited) @executable_path/Frameworks",
        "ENABLE_PREVIEWS": "YES", "SUPPORTED_PLATFORMS": "iphoneos iphonesimulator"
    }))
project_list = obj("project-configs", "XCConfigurationList", buildConfigurations=project_configs, defaultConfigurationIsVisible=0, defaultConfigurationName="Release")
target_list = obj("target-configs", "XCConfigurationList", buildConfigurations=target_configs, defaultConfigurationIsVisible=0, defaultConfigurationName="Release")
target = obj("target", "PBXNativeTarget", buildConfigurationList=target_list,
             buildPhases=[source_phase, framework_phase, resource_phase], buildRules=[], dependencies=[],
             name="ClickBridge", productName="ClickBridge", productReference=app,
             productType="com.apple.product-type.application", packageProductDependencies=product_dependencies)
project = obj("project", "PBXProject", attributes={"LastUpgradeCheck": "1600", "BuildIndependentTargetsInParallel": "YES"},
              buildConfigurationList=project_list, compatibilityVersion="Xcode 14.0", developmentRegion="de",
              hasScannedForEncodings=0, knownRegions=["de", "en", "Base"], mainGroup=group, productRefGroup=products,
              projectDirPath="", projectRoot="", targets=[target], packageReferences=[package])
output = ROOT / "ClickBridge.xcodeproj"
output.mkdir(exist_ok=True)
(output / "project.pbxproj").write_text("// !$*UTF8*$!\n" + encode({"archiveVersion": 1, "classes": {}, "objectVersion": 56, "objects": objects, "rootObject": project}) + "\n")
schemes = output / "xcshareddata/xcschemes"
schemes.mkdir(parents=True, exist_ok=True)
reference = f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="ClickBridge.app" BlueprintName="ClickBridge" ReferencedContainer="container:ClickBridge.xcodeproj"/>'
(schemes / "ClickBridge.xcscheme").write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.3">
 <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{reference}</BuildActionEntry></BuildActionEntries></BuildAction>
 <TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables/></TestAction>
 <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{reference}</BuildableProductRunnable></LaunchAction>
 <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{reference}</BuildableProductRunnable></ProfileAction>
 <AnalyzeAction buildConfiguration="Debug"/>
 <ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
''')
print(output)
