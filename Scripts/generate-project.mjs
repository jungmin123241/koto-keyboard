// Dependency-free, deterministic Xcode project generator. No shell build phases.
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath } from 'node:url';

export const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const id = name => crypto.createHash('sha256').update(name).digest('hex').slice(0, 24).toUpperCase();
const list = dir => fs.readdirSync(path.join(root, dir), { withFileTypes: true }).flatMap(entry => entry.isDirectory() ? list(`${dir}/${entry.name}`) : [`${dir}/${entry.name}`]);
export function model() {
  const objects = {};
  const add = (key, value) => { const ref = id(key); objects[ref] = value; return ref; };
  const files = [...list('App'), ...list('KeyboardExtension'), ...list('Shared'), ...list('Tests'), ...list('UITests'), ...list('TestHost'), ...list('Config')].sort();
  const refs = {};
  for (const file of files) {
    const type = file.endsWith('.swift') ? 'sourcecode.swift' : file.endsWith('.xcconfig') ? 'text.xcconfig' : file.endsWith('.entitlements') ? 'text.plist.entitlements' : 'text.plist.xml';
    refs[file] = add(`file:${file}`, { isa: 'PBXFileReference', lastKnownFileType: type, path: file, sourceTree: '<group>' });
  }
  const shared = files.filter(f => f.startsWith('Shared/') && f.endsWith('.swift'));
  const core = shared.filter(f => f.startsWith('Shared/Core/'));
  const targets = [
    { name: 'KotoKeyboard', kind: 'application', ext: 'app', sources: [...files.filter(f => f.startsWith('App/') && f.endsWith('.swift')), ...shared], info: 'App/Resources/Info.plist', entitlements: 'Config/App.entitlements', bundle: '$(APP_BUNDLE_IDENTIFIER)' },
    { name: 'KotoKeyboardExtension', kind: 'app-extension', ext: 'appex', sources: [...files.filter(f => f.startsWith('KeyboardExtension/') && f.endsWith('.swift')), ...shared], info: 'KeyboardExtension/Info.plist', entitlements: 'Config/Keyboard.entitlements', bundle: '$(APP_BUNDLE_IDENTIFIER).keyboard' },
    { name: 'KeyboardCoreTests', kind: 'bundle.unit-test', ext: 'xctest', sources: [...core, ...files.filter(f => f.startsWith('Tests/') && f.endsWith('.swift'))], bundle: '$(APP_BUNDLE_IDENTIFIER).core-tests' },
    { name: 'KotoKeyboardUITests', kind: 'bundle.ui-testing', ext: 'xctest', sources: files.filter(f => f.startsWith('UITests/') && f.endsWith('.swift')), bundle: '$(APP_BUNDLE_IDENTIFIER).ui-tests' },
    { name: 'KeyboardTestHost', kind: 'application', ext: 'app', sources: files.filter(f => f.startsWith('TestHost/') && f.endsWith('.swift')), bundle: '$(APP_BUNDLE_IDENTIFIER).test-host' }
  ];
  const products = targets.map(target => add(`product:${target.name}`, { isa: 'PBXFileReference', explicitFileType: target.ext === 'app' ? 'wrapper.application' : target.ext === 'appex' ? 'wrapper.app-extension' : 'wrapper.cfbundle', includeInIndex: '0', path: `${target.name}.${target.ext}`, sourceTree: 'BUILT_PRODUCTS_DIR' }));
  const productGroup = add('products', { isa: 'PBXGroup', children: products, name: 'Products', sourceTree: '<group>' });
  const mainGroup = add('mainGroup', { isa: 'PBXGroup', children: [...Object.values(refs), productGroup], sourceTree: '<group>' });
  const configurationList = (name, settings) => {
    const configurations = ['Debug', 'Release', 'FreeDevice'].map(config => {
      const buildSettings = { ...settings,
        SWIFT_OPTIMIZATION_LEVEL: config === 'Release' ? '-O' : '-Onone',
        ...(config !== 'Release' ? { SWIFT_ACTIVE_COMPILATION_CONDITIONS: config === 'FreeDevice' ? '$(inherited) DEBUG FREE_DEVICE_BUILD' : '$(inherited) DEBUG', ENABLE_TESTABILITY: 'YES', DEBUG_INFORMATION_FORMAT: 'dwarf' } : { DEBUG_INFORMATION_FORMAT: 'dwarf-with-dsym' }) };
      if (config === 'FreeDevice') delete buildSettings.CODE_SIGN_ENTITLEMENTS;
      return add(`config:${name}:${config}`, {
      isa: 'XCBuildConfiguration', baseConfigurationReference: refs['Config/Project.xcconfig'], name: config,
      buildSettings
    }); });
    return add(`configList:${name}`, { isa: 'XCConfigurationList', buildConfigurations: configurations, defaultConfigurationIsVisible: '0', defaultConfigurationName: 'Release' });
  };
  const projectConfig = configurationList('project', { SDKROOT: 'iphoneos', CLANG_ENABLE_MODULES: 'YES', CLANG_ENABLE_OBJC_ARC: 'YES', SWIFT_STRICT_CONCURRENCY: 'targeted', ENABLE_USER_SCRIPT_SANDBOXING: 'YES' });
  for (const [index, target] of targets.entries()) {
    const sources = target.sources.map(file => add(`build:${target.name}:${file}`, { isa: 'PBXBuildFile', fileRef: refs[file] }));
    const phases = [add(`sources:${target.name}`, { isa: 'PBXSourcesBuildPhase', buildActionMask: '2147483647', files: sources, runOnlyForDeploymentPostprocessing: '0' }),
      add(`frameworks:${target.name}`, { isa: 'PBXFrameworksBuildPhase', buildActionMask: '2147483647', files: [], runOnlyForDeploymentPostprocessing: '0' })];
    const resources = target.entitlements ? [add(`privacy:${target.name}`, { isa: 'PBXBuildFile', fileRef: refs['Shared/Resources/PrivacyInfo.xcprivacy'] })] : [];
    phases.push(add(`resources:${target.name}`, { isa: 'PBXResourcesBuildPhase', buildActionMask: '2147483647', files: resources, runOnlyForDeploymentPostprocessing: '0' }));
    const dependencies = [];
    const dependency = name => {
      const proxy = add(`proxy:${target.name}:${name}`, { isa: 'PBXContainerItemProxy', containerPortal: id('project'), proxyType: '1', remoteGlobalIDString: id(`target:${name}`), remoteInfo: name });
      dependencies.push(add(`dependency:${target.name}:${name}`, { isa: 'PBXTargetDependency', target: id(`target:${name}`), targetProxy: proxy }));
    };
    if (target.name === 'KotoKeyboard') {
      dependency('KotoKeyboardExtension');
      const embedded = add('embed-extension-build', { isa: 'PBXBuildFile', fileRef: products[1], settings: { ATTRIBUTES: ['RemoveHeadersOnCopy'] } });
      phases.push(add('embed-extension-phase', { isa: 'PBXCopyFilesBuildPhase', buildActionMask: '2147483647', dstPath: '', dstSubfolderSpec: '13', files: [embedded], name: 'Embed App Extensions', runOnlyForDeploymentPostprocessing: '0' }));
    }
    if (target.name === 'KotoKeyboardUITests') dependency('KotoKeyboard');
    const settings = { PRODUCT_NAME: '$(TARGET_NAME)', PRODUCT_BUNDLE_IDENTIFIER: target.bundle, TARGETED_DEVICE_FAMILY: '1', CODE_SIGN_STYLE: 'Automatic',
      SUPPORTED_PLATFORMS: 'iphoneos iphonesimulator', SUPPORTS_MACCATALYST: 'NO', SWIFT_EMIT_LOC_STRINGS: 'YES',
      LD_RUNPATH_SEARCH_PATHS: ['$(inherited)', '@executable_path/Frameworks', '@executable_path/../../Frameworks'],
      ...(target.info ? { INFOPLIST_FILE: target.info, GENERATE_INFOPLIST_FILE: 'NO' } : { GENERATE_INFOPLIST_FILE: 'YES' }),
      ...(target.entitlements ? { CODE_SIGN_ENTITLEMENTS: target.entitlements } : {}),
      ...(target.kind === 'app-extension' ? { APPLICATION_EXTENSION_API_ONLY: 'YES', SKIP_INSTALL: 'YES' } : {}),
      ...(target.kind === 'bundle.ui-testing' ? { TEST_TARGET_NAME: 'KotoKeyboard' } : {}),
      ...(target.kind === 'bundle.unit-test' || target.kind === 'bundle.ui-testing' ? { SKIP_INSTALL: 'YES' } : {}),
      ...(target.name === 'KeyboardTestHost' ? { INFOPLIST_KEY_UILaunchScreen_Generation: 'YES', INFOPLIST_KEY_UISupportedInterfaceOrientations: 'UIInterfaceOrientationPortrait' } : {}) };
    add(`target:${target.name}`, { isa: 'PBXNativeTarget', buildConfigurationList: configurationList(target.name, settings), buildPhases: phases, buildRules: [], dependencies, name: target.name, productName: target.name, productReference: products[index], productType: `com.apple.product-type.${target.kind}` });
  }
  add('project', { isa: 'PBXProject', attributes: { BuildIndependentTargetsInParallel: 'YES', LastUpgradeCheck: '1600' }, buildConfigurationList: projectConfig, compatibilityVersion: 'Xcode 14.0', developmentRegion: 'ko', knownRegions: ['ko', 'en', 'Base'], mainGroup, productRefGroup: productGroup, projectDirPath: '', projectRoot: '', targets: targets.map(t => id(`target:${t.name}`)) });
  return { archiveVersion: '1', classes: {}, objectVersion: '56', objects, rootObject: id('project') };
}

function serialize(value, depth = 0) {
  const indent = '\t'.repeat(depth);
  if (Array.isArray(value)) return `(\n${value.map(v => `${indent}\t${serialize(v, depth + 1)},`).join('\n')}\n${indent})`;
  if (value && typeof value === 'object') return `{\n${Object.entries(value).map(([k, v]) => `${indent}\t${JSON.stringify(k)} = ${serialize(v, depth + 1)};`).join('\n')}\n${indent}}`;
  return JSON.stringify(String(value));
}
export function generate() {
  const dir = path.join(root, 'KotoKeyboard.xcodeproj');
  fs.mkdirSync(path.join(dir, 'xcshareddata/xcschemes'), { recursive: true });
  fs.writeFileSync(path.join(dir, 'project.pbxproj'), '// !$*UTF8*$!\n' + serialize(model()) + '\n');
  const ref = (name, ext) => `<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="${id(`target:${name}`)}" BuildableName="${name}.${ext}" BlueprintName="${name}" ReferencedContainer="container:KotoKeyboard.xcodeproj"/>`;
  const scheme = `<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.3">
 <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries>
  <BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">${ref('KotoKeyboard', 'app')}</BuildActionEntry>
  <BuildActionEntry buildForTesting="YES" buildForRunning="NO" buildForProfiling="NO" buildForArchiving="NO" buildForAnalyzing="YES">${ref('KeyboardTestHost', 'app')}</BuildActionEntry>
 </BuildActionEntries></BuildAction>
 <TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables>
  <TestableReference skipped="NO">${ref('KeyboardCoreTests', 'xctest')}</TestableReference>
  <TestableReference skipped="NO">${ref('KotoKeyboardUITests', 'xctest')}</TestableReference>
 </Testables></TestAction>
 <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">${ref('KotoKeyboard', 'app')}</BuildableProductRunnable></LaunchAction>
 <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">${ref('KotoKeyboard', 'app')}</BuildableProductRunnable></ProfileAction>
 <AnalyzeAction buildConfiguration="Debug"/>
 <ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>\n`;
  fs.writeFileSync(path.join(dir, 'xcshareddata/xcschemes/KotoKeyboard.xcscheme'), scheme);
  const freeScheme = scheme
    .replaceAll('buildConfiguration="Debug"', 'buildConfiguration="FreeDevice"')
    .replaceAll('buildConfiguration="Release"', 'buildConfiguration="FreeDevice"');
  fs.writeFileSync(path.join(dir, 'xcshareddata/xcschemes/KotoKeyboard-FreeDevice.xcscheme'), freeScheme);
}
if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) generate();
