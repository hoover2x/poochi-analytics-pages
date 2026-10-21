#!/usr/bin/env python3
"""Generate the checked-in, dependency-free Xcode project deterministically."""
from pathlib import Path
from hashlib import sha1
import json

ROOT = Path(__file__).resolve().parent.parent
objects = {}

def ident(name):
    return sha1(name.encode()).hexdigest().upper()[:24]

def quoted(value):
    return json.dumps(value)

def add(name, content):
    objects[ident(name)] = content
    return ident(name)

def refs(values):
    return "(" + ", ".join(values) + ",)" if values else "()"

def settings(values):
    return "{ " + " ".join(f"{key} = {quoted(str(value))};" for key, value in values.items()) + " }"

def configurations(name, values):
    ids = []
    for mode in ("Debug", "Release"):
        actual = dict(values)
        actual["SWIFT_OPTIMIZATION_LEVEL"] = "-Onone" if mode == "Debug" else "-O"
        actual["DEBUG_INFORMATION_FORMAT"] = "dwarf" if mode == "Debug" else "dwarf-with-dsym"
        if mode == "Debug":
            actual["SWIFT_ACTIVE_COMPILATION_CONDITIONS"] = "DEBUG"
        ids.append(add(name + mode, f"isa = XCBuildConfiguration; buildSettings = {settings(actual)}; name = {mode};"))
    return add(name + "ConfigList", f"isa = XCConfigurationList; buildConfigurations = {refs(ids)}; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;")

source_files = sorted(p.relative_to(ROOT).as_posix() for p in (ROOT / "Sources").rglob("*.swift"))
test_files = ["UITests/PoochiUITests.swift"]
file_refs = []

def source_phase(name, files):
    build_refs = []
    for path in files:
        file_id = add(path + "File", f"isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {quoted(path)}; sourceTree = SOURCE_ROOT;")
        file_refs.append(file_id)
        build_refs.append(add(path + "Build", f"isa = PBXBuildFile; fileRef = {file_id};"))
    return add(name + "Sources", f"isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = {refs(build_refs)}; runOnlyForDeploymentPostprocessing = 0;")

app_sources = source_phase("App", source_files)
test_sources = source_phase("UITest", test_files)
app_product = add("AppProduct", 'isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = "Poochi Analytics.app"; sourceTree = BUILT_PRODUCTS_DIR;')
test_product = add("TestProduct", 'isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = PoochiUITests.xctest; sourceTree = BUILT_PRODUCTS_DIR;')
products = add("Products", f"isa = PBXGroup; children = {refs([app_product, test_product])}; name = Products; sourceTree = \"<group>\";")
source_group = add("Sources", f"isa = PBXGroup; children = {refs(file_refs)}; name = Sources; sourceTree = \"<group>\";")
resources = []
for path in ["Resources/Info.plist", "Resources/PoochiAnalytics.entitlements", "Package.swift", "README.md"]:
    kind = "text.plist.xml" if path.endswith((".plist", ".entitlements")) else "text"
    resources.append(add(path, f"isa = PBXFileReference; lastKnownFileType = {kind}; path = {quoted(path)}; sourceTree = SOURCE_ROOT;"))
resource_group = add("Resources", f"isa = PBXGroup; children = {refs(resources)}; name = Resources; sourceTree = \"<group>\";")
main = add("Main", f"isa = PBXGroup; children = {refs([source_group, resource_group, products])}; sourceTree = \"<group>\";")

common = {"MACOSX_DEPLOYMENT_TARGET": "13.0", "SDKROOT": "macosx", "SWIFT_VERSION": "5.0", "CLANG_ENABLE_MODULES": "YES",
          "SWIFT_STRICT_CONCURRENCY": "targeted", "CODE_SIGN_STYLE": "Automatic", "CODE_SIGN_IDENTITY": "-"}
project_configs = configurations("Project", common)
app_configs = configurations("App", {"PRODUCT_NAME": "Poochi Analytics", "PRODUCT_MODULE_NAME": "PoochiAnalytics",
    "PRODUCT_BUNDLE_IDENTIFIER": "com.hoover2x.PoochiAnalytics", "INFOPLIST_FILE": "Resources/Info.plist",
    "CODE_SIGN_ENTITLEMENTS": "Resources/PoochiAnalytics.entitlements", "ENABLE_HARDENED_RUNTIME": "YES",
    "COMBINE_HIDPI_IMAGES": "YES", "LD_RUNPATH_SEARCH_PATHS": "$(inherited) @executable_path/../Frameworks"})
test_configs = configurations("UITest", {"PRODUCT_NAME": "PoochiUITests", "PRODUCT_BUNDLE_IDENTIFIER": "com.hoover2x.PoochiAnalytics.UITests",
    "GENERATE_INFOPLIST_FILE": "YES", "TEST_TARGET_NAME": "PoochiAnalytics", "SWIFT_EMIT_LOC_STRINGS": "NO"})

app_target = ident("AppTarget")
test_target = ident("TestTarget")
project_id = ident("Project")
proxy = add("AppProxy", f"isa = PBXContainerItemProxy; containerPortal = {project_id}; proxyType = 1; remoteGlobalIDString = {app_target}; remoteInfo = PoochiAnalytics;")
dependency = add("AppDependency", f"isa = PBXTargetDependency; target = {app_target}; targetProxy = {proxy};")
add("AppTarget", f"isa = PBXNativeTarget; buildConfigurationList = {app_configs}; buildPhases = {refs([app_sources])}; buildRules = (); dependencies = (); name = PoochiAnalytics; productName = \"Poochi Analytics\"; productReference = {app_product}; productType = \"com.apple.product-type.application\";")
add("TestTarget", f"isa = PBXNativeTarget; buildConfigurationList = {test_configs}; buildPhases = {refs([test_sources])}; buildRules = (); dependencies = {refs([dependency])}; name = PoochiUITests; productName = PoochiUITests; productReference = {test_product}; productType = \"com.apple.product-type.bundle.ui-testing\";")
add("Project", f"isa = PBXProject; attributes = {{ BuildIndependentTargetsInParallel = YES; LastUpgradeCheck = 1600; TargetAttributes = {{ {test_target} = {{ TestTargetID = {app_target}; }}; }}; }}; buildConfigurationList = {project_configs}; compatibilityVersion = \"Xcode 14.0\"; developmentRegion = en; hasScannedForEncodings = 0; knownRegions = (en, Base,); mainGroup = {main}; productRefGroup = {products}; projectDirPath = \"\"; projectRoot = \"\"; targets = {refs([app_target, test_target])};")

project = ROOT / "PoochiAnalytics.xcodeproj"
project.mkdir(exist_ok=True)
body = "// !$*UTF8*$!\n{\n\tarchiveVersion = 1;\n\tclasses = {};\n\tobjectVersion = 56;\n\tobjects = {\n"
body += "\n".join(f"\t\t{key} = {{ {value} }};" for key, value in objects.items())
body += f"\n\t}};\n\trootObject = {project_id};\n}}\n"
(project / "project.pbxproj").write_text(body)
scheme_dir = project / "xcshareddata/xcschemes"
scheme_dir.mkdir(parents=True, exist_ok=True)

def reference(target, name):
    return f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="{name}" BlueprintName="{"PoochiAnalytics" if target == app_target else "PoochiUITests"}" ReferencedContainer="container:PoochiAnalytics.xcodeproj"/>'

app_ref = reference(app_target, "Poochi Analytics.app")
test_ref = reference(test_target, "PoochiUITests.xctest")
scheme = f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.3">
  <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries>
    <BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{app_ref}</BuildActionEntry>
  </BuildActionEntries></BuildAction>
  <TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO">{test_ref}</TestableReference></Testables></TestAction>
  <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{app_ref}</BuildableProductRunnable></LaunchAction>
  <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{app_ref}</BuildableProductRunnable></ProfileAction>
  <AnalyzeAction buildConfiguration="Debug"/>
  <ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
'''
(scheme_dir / "PoochiAnalytics.xcscheme").write_text(scheme)
print(f"Generated {project.name}: {len(source_files)} application sources and a native UI test target")
