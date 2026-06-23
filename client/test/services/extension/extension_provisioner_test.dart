import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/extension_manifest.dart';
import 'package:teampilot/services/extension/extension_detector.dart';
import 'package:teampilot/services/extension/extension_provisioner.dart';
import 'package:teampilot/services/host/host_execution_environment.dart';
import 'package:teampilot/services/host/host_script_runner.dart';
import 'package:teampilot/services/host/script_file_hook_provisioner.dart';
import 'package:teampilot/services/storage/runtime_context.dart';
import '../../support/in_memory_filesystem.dart';

ProcessResult _ok(String stdout) => ProcessResult(0, 0, stdout, '');
ProcessResult _fail() => ProcessResult(0, 1, '', '');

ExtensionManifest get _rtkManifest => ExtensionManifest.fromJson({
      'id': 'rtk',
      'name': 'RTK',
      'detect': {
        'executable': 'rtk',
        'minVersion': '0.23.0',
        'requires': ['jq'],
      },
      'effects': [
        {
          'kind': 'settings-hook',
          'event': 'PreToolUse',
          'matcher': 'Bash',
          'scriptAsset': 'rtk-rewrite',
          'marker': 'rtk-rewrite',
        },
      ],
    });

ExtensionDetector _detectorAllReady() => ExtensionDetector(
      processRunner: (exe, args, {environment}) async {
        if (args.length == 1 && (args.first == 'rtk' || args.first == 'jq')) {
          return _ok('/usr/bin/${args.first}');
        }
        if (args.contains('--version')) return _ok('rtk 0.24.1');
        return _fail();
      },
    );

ExtensionProvisioner _provisioner({
  required bool enabled,
  required ExtensionDetector detector,
  required InMemoryFilesystem fs,
}) {
  final host = HostExecutionEnvironment.resolve(
    isWindowsHost: false,
    storageMode: StorageBackendMode.native,
  );
  final runner = HostScriptRunner(host);
  return ExtensionProvisioner(
    manifests: [_rtkManifest],
    isEnabled: (id) async => id == 'rtk' && enabled,
    detector: detector,
    hookProvisionerFor: (scriptAsset) => ScriptFileHookProvisioner(
      fs: fs,
      runner: runner,
      baseFileName: scriptAsset,
      loadScript: (dialect) async => '#!/usr/bin/env bash\n# $scriptAsset\n',
    ),
  );
}

void main() {
  test('collectWarnings: empty when extension disabled', () async {
    final p = _provisioner(
      enabled: false,
      detector: _detectorAllReady(),
      fs: InMemoryFilesystem(),
    );
    expect(await p.collectWarnings(), isEmpty);
  });

  test('collectWarnings: not-found code when binary missing', () async {
    final detector = ExtensionDetector(
      processRunner: (exe, args, {environment}) async => _fail(),
    );
    final p = _provisioner(
      enabled: true,
      detector: detector,
      fs: InMemoryFilesystem(),
    );
    expect(await p.collectWarnings(), ['rtk_enabled_not_found']);
  });

  test('collectWarnings: dependency-missing code when jq absent', () async {
    final detector = ExtensionDetector(
      processRunner: (exe, args, {environment}) async {
        if (args.length == 1 && args.first == 'rtk') return _ok('/usr/bin/rtk');
        if (args.length == 1 && args.first == 'jq') return _fail();
        if (args.contains('--version')) return _ok('rtk 0.24.1');
        return _fail();
      },
    );
    final p = _provisioner(
      enabled: true,
      detector: detector,
      fs: InMemoryFilesystem(),
    );
    expect(await p.collectWarnings(), ['rtk_enabled_dependency_missing']);
  });

  test('collectWarnings: version-too-old code', () async {
    final detector = ExtensionDetector(
      processRunner: (exe, args, {environment}) async {
        if (args.length == 1 && (args.first == 'rtk' || args.first == 'jq')) {
          return _ok('/usr/bin/${args.first}');
        }
        if (args.contains('--version')) return _ok('rtk 0.22.0');
        return _fail();
      },
    );
    final p = _provisioner(
      enabled: true,
      detector: detector,
      fs: InMemoryFilesystem(),
    );
    expect(await p.collectWarnings(), ['rtk_enabled_version_too_old']);
  });

  test('applySettings: no-op when memberToolDir empty', () async {
    final p = _provisioner(
      enabled: true,
      detector: _detectorAllReady(),
      fs: InMemoryFilesystem(),
    );
    expect(await p.applySettings({'model': 'x'}, ''), {'model': 'x'});
  });

  test('applySettings: merges hook when enabled and ready', () async {
    final fs = InMemoryFilesystem();
    final p = _provisioner(
      enabled: true,
      detector: _detectorAllReady(),
      fs: fs,
    );
    final result = await p.applySettings({}, '/member/flashskyai');
    final pre = (result['hooks'] as Map)['PreToolUse'] as List;
    expect(pre, hasLength(1));
    final command = ((pre.single as Map)['hooks'] as List).single as Map;
    expect(command['command'], contains('rtk-rewrite.sh'));
  });

  test('applySettings: no-op when not ready', () async {
    final detector = ExtensionDetector(
      processRunner: (exe, args, {environment}) async => _fail(),
    );
    final p = _provisioner(
      enabled: true,
      detector: detector,
      fs: InMemoryFilesystem(),
    );
    expect(await p.applySettings({}, '/member/flashskyai'), {});
  });
}
