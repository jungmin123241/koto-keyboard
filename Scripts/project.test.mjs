import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { model, root } from './generate-project.mjs';

test('all five Xcode targets reference existing sources and configurations', () => {
  const project = model();
  const targets = Object.values(project.objects).filter(o => o.isa === 'PBXNativeTarget');
  assert.equal(targets.length, 5);
  for (const file of Object.values(project.objects).filter(o => o.isa === 'PBXFileReference' && o.sourceTree === '<group>')) {
    assert.ok(fs.existsSync(path.join(root, file.path)), file.path);
  }
  for (const target of targets) {
    assert.ok(project.objects[target.buildConfigurationList]);
    for (const phase of target.buildPhases) assert.ok(project.objects[phase]);
    for (const dependency of target.dependencies) assert.ok(project.objects[dependency]);
  }
});
test('host embeds extension and extension cannot call app-only APIs', () => {
  const objects = model().objects;
  const app = Object.values(objects).find(o => o.isa === 'PBXNativeTarget' && o.name === 'KotoKeyboard');
  const copy = app.buildPhases.map(id => objects[id]).find(o => o.isa === 'PBXCopyFilesBuildPhase');
  assert.equal(copy.dstSubfolderSpec, '13');
  assert.equal(objects[objects[copy.files[0]].fileRef].path, 'KotoKeyboardExtension.appex');
  const extension = Object.values(objects).find(o => o.isa === 'PBXNativeTarget' && o.name === 'KotoKeyboardExtension');
  for (const config of objects[extension.buildConfigurationList].buildConfigurations) {
    assert.equal(objects[config].buildSettings.APPLICATION_EXTENSION_API_ONLY, 'YES');
    if (objects[config].name === 'FreeDevice') assert.equal(objects[config].buildSettings.CODE_SIGN_ENTITLEMENTS, undefined);
    else assert.equal(objects[config].buildSettings.CODE_SIGN_ENTITLEMENTS, 'Config/Keyboard.entitlements');
  }
});
test('app and extension both include the privacy manifest and common core', () => {
  const objects = model().objects;
  for (const name of ['KotoKeyboard', 'KotoKeyboardExtension']) {
    const target = Object.values(objects).find(o => o.isa === 'PBXNativeTarget' && o.name === name);
    const paths = target.buildPhases.flatMap(id => objects[id].files ?? []).map(id => objects[objects[id].fileRef].path);
    assert.ok(paths.includes('Shared/Resources/PrivacyInfo.xcprivacy'));
    assert.ok(paths.includes('Shared/Core/HangulComposer.swift'));
    assert.ok(paths.includes('Shared/Core/DocumentEditing.swift'));
  }
});
test('all build files are unique per target and all dependency proxies resolve', () => {
  const objects = model().objects;
  for (const target of Object.values(objects).filter(object => object.isa === 'PBXNativeTarget')) {
    const buildFiles = target.buildPhases.flatMap(reference => objects[reference].files ?? []);
    assert.equal(new Set(buildFiles).size, buildFiles.length, `${target.name} contains duplicate build files`);
    for (const dependencyReference of target.dependencies) {
      const dependency = objects[dependencyReference];
      assert.ok(objects[dependency.target], `${target.name} dependency target is missing`);
      assert.ok(objects[dependency.targetProxy], `${target.name} dependency proxy is missing`);
      assert.equal(objects[dependency.targetProxy].remoteGlobalIDString, dependency.target);
    }
  }
});
test('required privacy and keyboard configuration is present', () => {
  const privacy = fs.readFileSync(path.join(root, 'Shared/Resources/PrivacyInfo.xcprivacy'), 'utf8');
  const keyboardInfo = fs.readFileSync(path.join(root, 'KeyboardExtension/Info.plist'), 'utf8');
  assert.match(privacy, /NSPrivacyAccessedAPICategoryUserDefaults/);
  assert.match(privacy, /1C8F\.1/);
  assert.match(keyboardInfo, /com\.apple\.keyboard-service/);
  assert.match(keyboardInfo, /RequestsOpenAccess/);
  assert.match(keyboardInfo, /SharedAppGroup/);
  assert.match(keyboardInfo, /SharedKeychainGroup/);
});
test('free device configuration removes paid capabilities from app and extension', () => {
  const objects = model().objects;
  for (const name of ['KotoKeyboard', 'KotoKeyboardExtension']) {
    const target = Object.values(objects).find(object => object.isa === 'PBXNativeTarget' && object.name === name);
    const configs = objects[target.buildConfigurationList].buildConfigurations.map(reference => objects[reference]);
    const free = configs.find(config => config.name === 'FreeDevice');
    assert.equal(free.buildSettings.CODE_SIGN_ENTITLEMENTS, undefined);
    assert.match(free.buildSettings.SWIFT_ACTIVE_COMPILATION_CONDITIONS, /FREE_DEVICE_BUILD/);
    for (const config of configs.filter(config => config.name !== 'FreeDevice')) {
      assert.match(config.buildSettings.CODE_SIGN_ENTITLEMENTS, /\.entitlements$/);
    }
  }
});
test('free device scheme exists and selects the free configuration', () => {
  const schemePath = path.join(root, 'KotoKeyboard.xcodeproj/xcshareddata/xcschemes/KotoKeyboard-FreeDevice.xcscheme');
  assert.ok(fs.existsSync(schemePath));
  const scheme = fs.readFileSync(schemePath, 'utf8');
  assert.match(scheme, /buildConfiguration="FreeDevice"/);
  assert.doesNotMatch(scheme, /buildConfiguration="Debug"/);
  assert.doesNotMatch(scheme, /buildConfiguration="Release"/);
  assert.match(scheme, /BlueprintName="KotoKeyboard"/);
});
