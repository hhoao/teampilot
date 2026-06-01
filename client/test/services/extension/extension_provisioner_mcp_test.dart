import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/extension_manifest.dart';
import 'package:teampilot/services/extension/extension_detector.dart';
import 'package:teampilot/services/extension/extension_provisioner.dart';

ProcessResult _ok(String s) => ProcessResult(0, 0, s, '');
ProcessResult _fail() => ProcessResult(0, 1, '', '');

ExtensionManifest get _codegraph => ExtensionManifest.fromJson({
      'id': 'codegraph',
      'name': 'CodeGraph',
      'detect': {'executable': 'codegraph', 'versionArgs': ['--version']},
      'effects': [
        {
          'kind': 'mcp-server',
          'appliesTo': ['claude', 'flashskyai'],
          'name': 'codegraph',
          'server': {'command': 'codegraph', 'args': ['serve', '--mcp']},
        },
      ],
    });

ExtensionProvisioner _provisioner({
  required bool enabled,
  required ExtensionDetector detector,
}) =>
    ExtensionProvisioner(
      manifests: [_codegraph],
      isEnabled: (id) async => id == 'codegraph' && enabled,
      detector: detector,
    );

ExtensionDetector _present() => ExtensionDetector(
      processRunner: (exe, args, {environment}) async {
        if (args.length == 1 && args.first == 'codegraph') {
          return _ok('/usr/bin/codegraph');
        }
        if (args.contains('--version')) return _ok('codegraph 1.4.0');
        return _fail();
      },
    );

void main() {
  test('contributes an McpServer when enabled and present', () async {
    final servers =
        await _provisioner(enabled: true, detector: _present()).collectMcpContributions();
    expect(servers, hasLength(1));
    final s = servers.single;
    expect(s.id, 'ext:codegraph');
    expect(s.name, 'codegraph');
    expect(s.enabled, isTrue);
    expect(s.server['command'], 'codegraph');
    expect(s.server['args'], ['serve', '--mcp']);
  });

  test('no contribution when disabled', () async {
    final servers =
        await _provisioner(enabled: false, detector: _present()).collectMcpContributions();
    expect(servers, isEmpty);
  });

  test('no contribution when tool not present', () async {
    final detector = ExtensionDetector(
      processRunner: (exe, args, {environment}) async => _fail(),
    );
    final servers =
        await _provisioner(enabled: true, detector: detector).collectMcpContributions();
    expect(servers, isEmpty);
  });
}
