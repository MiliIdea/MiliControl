#!/usr/bin/env python3
# Regenerates MiliControl.xcodeproj from the file list below.
# Usage (from repo root):  python3 Scripts/generate_project.py .
# Add new source files to `tree`, then re-run.
import hashlib, os, re, sys
ROOT = sys.argv[1]
SRC = "MiliControl"
TEAM = "JK772YMH8E"
BUNDLE = "com.mili.MiliControl"

# Swift packages: (product, repository URL, minimum version — up to next major).
PACKAGES = [
    ("Sparkle", "https://github.com/sparkle-project/Sparkle", "2.6.0"),
]

# Version and build are edited in Xcode (target ▸ General); keep them when
# regenerating instead of resetting to 1.0.0 (1).
def existing_setting(name, default):
    path = os.path.join(ROOT, "MiliControl.xcodeproj", "project.pbxproj")
    if os.path.exists(path):
        match = re.search(rf"\b{name} = ([^;]+);", open(path).read())
        if match:
            return match.group(1).strip()
    return default
MARKETING_VERSION = existing_setting("MARKETING_VERSION", "1.0.0")
BUILD_NUMBER = existing_setting("CURRENT_PROJECT_VERSION", "1")

def uid(*parts):
    return hashlib.md5("|".join(parts).encode()).hexdigest()[:24].upper()

# Group tree: (group name, relative path, children); children are file names or nested groups
tree = ("MiliControl", "MiliControl", [
    ("App", "App", ["main.swift", "AppDelegate.swift", "Preferences.swift", "LayoutStore.swift", "AppFonts.swift"]),
    ("Core", "Core", ["GridLayout.swift", "Navigator.swift", "RoutePlanner.swift"]),
    ("System", "System", ["CGSPrivate.swift", "DesktopStore.swift", "SymbolicHotKeys.swift",
                          "DesktopSwitcher.swift", "HotKeyCenter.swift", "SetupChecker.swift", "LoginItem.swift", "DockController.swift", "ScreenCapture.swift", "SystemPreferences.swift", "TrackpadSwipes.swift", "BrowserProfiles.swift", "WindowActivator.swift", "NowPlaying.swift", "MessageMonitor.swift"]),
    ("Features", "Features", [
        ("Shared", "Shared", ["VisualEffectBackground.swift"]),
        ("Navigation", "Navigation", ["NavigationCoordinator.swift", "HUD.swift"]),
        ("GridEditor", "GridEditor", ["GridEditorController.swift", "GridEditorView.swift"]),
        ("Settings", "Settings", ["SettingsWindowController.swift", "SettingsView.swift"]),
        ("MenuBar", "MenuBar", ["StatusBarController.swift"]),
        ("Dock", "Dock", ["DockCoordinator.swift"]),
        ("Previews", "Previews", ["DesktopSnapshots.swift"]),
        ("Updates", "Updates", ["UpdateController.swift"]),
        ("Dashboard", "Dashboard", ["DashboardStore.swift", "TodoStore.swift", "DashboardView.swift"]),
        ("Notch", "Notch", ["NotchController.swift", "NotchView.swift"]),
        ("WebTabs", "WebTabs", ["WebTabs.swift", "WebTabViews.swift"]),
    ]),
    ("Resources", "Resources", ["Assets.xcassets", "Info.plist", "MiliControl.entitlements"]
        # Bundled fonts (a folder reference, copied as Contents/Resources/Fonts).
        + (["Fonts"] if os.path.isdir(os.path.join(ROOT, "MiliControl/Resources/Fonts")) else [])),
])

filerefs, buildfiles, groups = [], [], []
sources, resources = [], []

def ftype(name):
    if name.endswith(".swift"): return "sourcecode.swift"
    if name.endswith(".xcassets"): return "folder.assetcatalog"
    if name.endswith(".plist"): return "text.plist.xml"
    if name.endswith(".entitlements"): return "text.plist.entitlements"
    if name == "Fonts": return "folder"
    return "text"

def walk(node, fs_path):
    name, path, children = node
    full = os.path.join(fs_path, path)
    gid = uid("group", full)
    child_ids = []
    for c in children:
        if isinstance(c, tuple):
            child_ids.append((walk(c, full), c[0]))
        else:
            fpath = os.path.join(full, c)
            assert os.path.exists(os.path.join(ROOT, fpath)), f"missing {fpath}"
            fid = uid("file", fpath)
            filerefs.append(f'\t\t{fid} /* {c} */ = {{isa = PBXFileReference; lastKnownFileType = {ftype(c)}; path = {q(c)}; sourceTree = "<group>"; }};')
            child_ids.append((fid, c))
            if c.endswith(".swift"):
                bid = uid("build", fpath)
                buildfiles.append(f'\t\t{bid} /* {c} in Sources */ = {{isa = PBXBuildFile; fileRef = {fid} /* {c} */; }};')
                sources.append((bid, c))
            elif c.endswith(".xcassets") or c == "Fonts":
                bid = uid("build", fpath)
                buildfiles.append(f'\t\t{bid} /* {c} in Resources */ = {{isa = PBXBuildFile; fileRef = {fid} /* {c} */; }};')
                resources.append((bid, c))
    kids = "\n".join(f"\t\t\t\t{i} /* {n} */," for i, n in child_ids)
    groups.append(f'\t\t{gid} /* {name} */ = {{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n{kids}\n\t\t\t);\n\t\t\tpath = {q(path)};\n\t\t\tsourceTree = "<group>";\n\t\t}};')
    return gid

def q(s):
    import re
    return s if re.fullmatch(r"[A-Za-z0-9_./$]+", s) else '"' + s + '"'

src_group = walk(tree, "")
MAIN, PRODUCTS, PROJECT, TARGET = uid("main"), uid("products"), uid("project"), uid("target")
APP = uid("product-app")
SRC_PHASE, FW_PHASE, RES_PHASE = uid("phase-src"), uid("phase-fw"), uid("phase-res")
PCL, TCL = uid("cl-project"), uid("cl-target")
PDBG, PREL, TDBG, TREL = uid("p-debug"), uid("p-release"), uid("t-debug"), uid("t-release")

filerefs.insert(0, f'\t\t{APP} /* MiliControl.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = MiliControl.app; sourceTree = BUILT_PRODUCTS_DIR; }};')
groups.append(f'\t\t{MAIN} = {{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n\t\t\t\t{src_group} /* MiliControl */,\n\t\t\t\t{PRODUCTS} /* Products */,\n\t\t\t);\n\t\t\tsourceTree = "<group>";\n\t\t}};')
groups.append(f'\t\t{PRODUCTS} /* Products */ = {{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n\t\t\t\t{APP} /* MiliControl.app */,\n\t\t\t);\n\t\t\tname = Products;\n\t\t\tsourceTree = "<group>";\n\t\t}};')

# Swift package references, product dependencies, and their Frameworks entries.
pkg_refs, pkg_deps, frameworks = [], [], []
for product, url, minimum in PACKAGES:
    ref_id, dep_id, fw_id = uid("pkg-ref", url), uid("pkg-dep", product), uid("pkg-fw", product)
    pkg_refs.append((ref_id, product,
        f'\t\t{ref_id} /* XCRemoteSwiftPackageReference "{product}" */ = {{\n'
        f'\t\t\tisa = XCRemoteSwiftPackageReference;\n'
        f'\t\t\trepositoryURL = "{url}";\n'
        f'\t\t\trequirement = {{\n\t\t\t\tkind = upToNextMajorVersion;\n\t\t\t\tminimumVersion = {minimum};\n\t\t\t}};\n'
        f'\t\t}};'))
    pkg_deps.append((dep_id, product,
        f'\t\t{dep_id} /* {product} */ = {{\n'
        f'\t\t\tisa = XCSwiftPackageProductDependency;\n'
        f'\t\t\tpackage = {ref_id} /* XCRemoteSwiftPackageReference "{product}" */;\n'
        f'\t\t\tproductName = {product};\n'
        f'\t\t}};'))
    buildfiles.append(f'\t\t{fw_id} /* {product} in Frameworks */ = {{isa = PBXBuildFile; productRef = {dep_id} /* {product} */; }};')
    frameworks.append((fw_id, product))

def phase(pid, isa, name, items):
    files = "\n".join(f"\t\t\t\t{b} /* {n} in {name} */," for b, n in items)
    return f'\t\t{pid} /* {name} */ = {{\n\t\t\tisa = {isa};\n\t\t\tbuildActionMask = 2147483647;\n\t\t\tfiles = (\n{files}\n\t\t\t);\n\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t}};'

common_project = """ALWAYS_SEARCH_USER_PATHS = NO;
				CLANG_ANALYZER_NONNULL = YES;
				CLANG_ENABLE_MODULES = YES;
				CLANG_ENABLE_OBJC_ARC = YES;
				COPY_PHASE_STRIP = NO;
				ENABLE_STRICT_OBJC_MSGSEND = YES;
				GCC_NO_COMMON_BLOCKS = YES;
				MACOSX_DEPLOYMENT_TARGET = 13.0;
				SDKROOT = macosx;
				SWIFT_VERSION = 5.0;"""
proj_debug = common_project + """
				DEBUG_INFORMATION_FORMAT = dwarf;
				ENABLE_TESTABILITY = YES;
				GCC_OPTIMIZATION_LEVEL = 0;
				GCC_PREPROCESSOR_DEFINITIONS = (
					"DEBUG=1",
					"$(inherited)",
				);
				ONLY_ACTIVE_ARCH = YES;
				SWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;
				SWIFT_OPTIMIZATION_LEVEL = "-Onone";"""
proj_release = common_project + """
				DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";
				ENABLE_NS_ASSERTIONS = NO;
				SWIFT_COMPILATION_MODE = wholemodule;
				SWIFT_OPTIMIZATION_LEVEL = "-O";"""
target_settings = f"""ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
				CODE_SIGN_ENTITLEMENTS = MiliControl/Resources/MiliControl.entitlements;
				CODE_SIGN_STYLE = Automatic;
				COMBINE_HIDPI_IMAGES = YES;
				CURRENT_PROJECT_VERSION = {BUILD_NUMBER};
				DEAD_CODE_STRIPPING = YES;
				DEVELOPMENT_TEAM = {TEAM};
				ENABLE_HARDENED_RUNTIME = YES;
				GENERATE_INFOPLIST_FILE = NO;
				INFOPLIST_FILE = MiliControl/Resources/Info.plist;
				LD_RUNPATH_SEARCH_PATHS = (
					"$(inherited)",
					"@executable_path/../Frameworks",
				);
				MARKETING_VERSION = {MARKETING_VERSION};
				PRODUCT_BUNDLE_IDENTIFIER = {BUNDLE};
				PRODUCT_NAME = MiliControl;
				SWIFT_EMIT_LOC_STRINGS = YES;"""

def cfg(cid, name, settings):
    return f'\t\t{cid} /* {name} */ = {{\n\t\t\tisa = XCBuildConfiguration;\n\t\t\tbuildSettings = {{\n\t\t\t\t{settings}\n\t\t\t}};\n\t\t\tname = {name};\n\t\t}};'

out = f"""// !$*UTF8*$!
{{
	archiveVersion = 1;
	classes = {{
	}};
	objectVersion = 56;
	objects = {{

/* Begin PBXBuildFile section */
{chr(10).join(sorted(buildfiles))}
/* End PBXBuildFile section */

/* Begin PBXFileReference section */
{chr(10).join(filerefs)}
/* End PBXFileReference section */

/* Begin PBXFrameworksBuildPhase section */
{phase(FW_PHASE, "PBXFrameworksBuildPhase", "Frameworks", frameworks)}
/* End PBXFrameworksBuildPhase section */

/* Begin PBXGroup section */
{chr(10).join(groups)}
/* End PBXGroup section */

/* Begin PBXNativeTarget section */
		{TARGET} /* MiliControl */ = {{
			isa = PBXNativeTarget;
			buildConfigurationList = {TCL} /* Build configuration list for PBXNativeTarget "MiliControl" */;
			buildPhases = (
				{SRC_PHASE} /* Sources */,
				{FW_PHASE} /* Frameworks */,
				{RES_PHASE} /* Resources */,
			);
			buildRules = (
			);
			dependencies = (
			);
			name = MiliControl;
			packageProductDependencies = (
{chr(10).join(f"				{i} /* {n} */," for i, n, _ in pkg_deps)}
			);
			productName = MiliControl;
			productReference = {APP} /* MiliControl.app */;
			productType = "com.apple.product-type.application";
		}};
/* End PBXNativeTarget section */

/* Begin PBXProject section */
		{PROJECT} /* Project object */ = {{
			isa = PBXProject;
			attributes = {{
				BuildIndependentTargetsInParallel = 1;
				LastSwiftUpdateCheck = 1500;
				LastUpgradeCheck = 1500;
				TargetAttributes = {{
					{TARGET} = {{
						CreatedOnToolsVersion = 15.0;
					}};
				}};
			}};
			buildConfigurationList = {PCL} /* Build configuration list for PBXProject "MiliControl" */;
			compatibilityVersion = "Xcode 14.0";
			developmentRegion = en;
			hasScannedForEncodings = 0;
			knownRegions = (
				en,
				Base,
			);
			mainGroup = {MAIN};
			packageReferences = (
{chr(10).join(f'				{i} /* XCRemoteSwiftPackageReference "{n}" */,' for i, n, _ in pkg_refs)}
			);
			productRefGroup = {PRODUCTS} /* Products */;
			projectDirPath = "";
			projectRoot = "";
			targets = (
				{TARGET} /* MiliControl */,
			);
		}};
/* End PBXProject section */

/* Begin PBXResourcesBuildPhase section */
{phase(RES_PHASE, "PBXResourcesBuildPhase", "Resources", resources)}
/* End PBXResourcesBuildPhase section */

/* Begin PBXSourcesBuildPhase section */
{phase(SRC_PHASE, "PBXSourcesBuildPhase", "Sources", sources)}
/* End PBXSourcesBuildPhase section */

/* Begin XCBuildConfiguration section */
{cfg(PDBG, "Debug", proj_debug)}
{cfg(PREL, "Release", proj_release)}
{cfg(TDBG, "Debug", target_settings)}
{cfg(TREL, "Release", target_settings)}
/* End XCBuildConfiguration section */

/* Begin XCConfigurationList section */
		{PCL} /* Build configuration list for PBXProject "MiliControl" */ = {{
			isa = XCConfigurationList;
			buildConfigurations = (
				{PDBG} /* Debug */,
				{PREL} /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		}};
		{TCL} /* Build configuration list for PBXNativeTarget "MiliControl" */ = {{
			isa = XCConfigurationList;
			buildConfigurations = (
				{TDBG} /* Debug */,
				{TREL} /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		}};
/* End XCConfigurationList section */

/* Begin XCRemoteSwiftPackageReference section */
{chr(10).join(block for _, _, block in pkg_refs)}
/* End XCRemoteSwiftPackageReference section */

/* Begin XCSwiftPackageProductDependency section */
{chr(10).join(block for _, _, block in pkg_deps)}
/* End XCSwiftPackageProductDependency section */
	}};
	rootObject = {PROJECT} /* Project object */;
}}
"""
proj = os.path.join(ROOT, "MiliControl.xcodeproj")
os.makedirs(os.path.join(proj, "xcshareddata", "xcschemes"), exist_ok=True)
open(os.path.join(proj, "project.pbxproj"), "w").write(out)

ref = f'''<BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "{TARGET}"
               BuildableName = "MiliControl.app"
               BlueprintName = "MiliControl"
               ReferencedContainer = "container:MiliControl.xcodeproj">
            </BuildableReference>'''
from xml.sax.saxutils import quoteattr
# Runs after every successful build (after code signing), so the installed
# copy is always the freshly signed one. Log: /tmp/MiliControl-install.log
INSTALL = """exec > /tmp/MiliControl-install.log 2>&1
set -e
SRC="${BUILT_PRODUCTS_DIR}/${FULL_PRODUCT_NAME}"
DST="/Applications/${FULL_PRODUCT_NAME}"
if [ ! -d "$SRC" ]; then echo "No build product at $SRC"; exit 1; fi
pkill -x "${PRODUCT_NAME}" || true
sleep 0.5
rm -rf "$DST"
ditto "$SRC" "$DST"
echo "Installed $DST from $SRC"
"""
install_script = quoteattr(INSTALL).replace("\n", "&#10;")
scheme = f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion = "1500" version = "1.7">
   <BuildAction parallelizeBuildables = "YES" buildImplicitDependencies = "YES">
      <PostActions>
         <ExecutionAction ActionType = "Xcode.IDEStandardExecutionActionsCore.ExecutionActionType.ShellScriptAction">
            <ActionContent title = "Install to /Applications" scriptText = {install_script}>
               <EnvironmentBuildable>
            {ref}
               </EnvironmentBuildable>
            </ActionContent>
         </ExecutionAction>
      </PostActions>
      <BuildActionEntries>
         <BuildActionEntry buildForTesting = "YES" buildForRunning = "YES" buildForProfiling = "YES" buildForArchiving = "YES" buildForAnalyzing = "YES">
            {ref}
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv = "YES">
   </TestAction>
   <LaunchAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" launchStyle = "0" useCustomWorkingDirectory = "NO" ignoresPersistentStateOnLaunch = "NO" debugDocumentVersioning = "YES" debugServiceExtension = "internal" allowLocationSimulation = "YES">
      <PathRunnable runnableDebuggingMode = "0" FilePath = "/Applications/MiliControl.app">
      </PathRunnable>
      <MacroExpansion>
            {ref}
      </MacroExpansion>
   </LaunchAction>
   <ProfileAction buildConfiguration = "Release" shouldUseLaunchSchemeArgsEnv = "YES" savedToolIdentifier = "" useCustomWorkingDirectory = "NO" debugDocumentVersioning = "YES">
      <BuildableProductRunnable runnableDebuggingMode = "0">
            {ref}
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction buildConfiguration = "Debug">
   </AnalyzeAction>
   <ArchiveAction buildConfiguration = "Release" revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
'''
open(os.path.join(proj, "xcshareddata", "xcschemes", "MiliControl.xcscheme"), "w").write(scheme)
print("sources", len(sources), "resources", len(resources), "groups", len(groups))
