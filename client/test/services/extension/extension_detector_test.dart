import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/extension_manifest.dart';
import 'package:teampilot/services/extension/extension_detector.dart';

ProcessResult _ok(String stdout) => ProcessResult(0, 0, stdout, '');
ProcessResult _fail() => ProcessResult(0, 1, '', 'not found');

void main() {
  const rtkDetect = ExtensionDetectSpec(
    executable: 'rtk',
    versionArgs: ['--version'],
    minVersion: '0.23.0',
    requires: ['jq'],
  );

  test('found with version and jq present is ready', () async {
    final detector = ExtensionDetector(
      processRunner: (exe, args, {environment}) async {
        if (args.length == 1 && args.first == 'rtk') return _ok('/usr/bin/rtk');
        if (args.length == 1 && args.first == 'jq') return _ok('/usr/bin/jq');
        if (args.contains('--version')) return _ok('rtk 0.24.1');
        return _fail();
      },
    );

    final probe = await detector.probe(rtkDetect);

    expect(probe.found, isTrue);
    expect(probe.executablePath, '/usr/bin/rtk');
    expect(probe.version, '0.24.1');
    expect(probe.satisfiesMinVersion, isTrue);
    expect(probe.missingRequirements, isEmpty);
    expect(probe.isReady, isTrue);
  });

  test('not found returns found=false', () async {
    final detector = ExtensionDetector(
      processRunner: (exe, args, {environment}) async => _fail(),
    );
    final probe = await detector.probe(rtkDetect);
    expect(probe.found, isFalse);
    expect(probe.isReady, isFalse);
  });

  test('missing requirement is reported', () async {
    final detector = ExtensionDetector(
      processRunner: (exe, args, {environment}) async {
        if (args.length == 1 && args.first == 'rtk') return _ok('/usr/bin/rtk');
        if (args.length == 1 && args.first == 'jq') return _fail();
        if (args.contains('--version')) return _ok('rtk 0.24.1');
        return _fail();
      },
    );
    final probe = await detector.probe(rtkDetect);
    expect(probe.found, isTrue);
    expect(probe.missingRequirements, ['jq']);
    expect(probe.isReady, isFalse);
  });

  test('version below minVersion fails satisfiesMinVersion', () async {
    final detector = ExtensionDetector(
      processRunner: (exe, args, {environment}) async {
        if (args.length == 1 && args.first == 'rtk') return _ok('/usr/bin/rtk');
        if (args.length == 1 && args.first == 'jq') return _ok('/usr/bin/jq');
        if (args.contains('--version')) return _ok('rtk 0.22.9');
        return _fail();
      },
    );
    final probe = await detector.probe(rtkDetect);
    expect(probe.version, '0.22.9');
    expect(probe.satisfiesMinVersion, isFalse);
    expect(probe.isReady, isFalse);
  });

  test('unparseable version is treated as satisfying (no false alarm)', () async {
    final detector = ExtensionDetector(
      processRunner: (exe, args, {environment}) async {
        if (args.length == 1 && args.first == 'rtk') return _ok('/usr/bin/rtk');
        if (args.length == 1 && args.first == 'jq') return _ok('/usr/bin/jq');
        if (args.contains('--version')) return _ok('rtk dev-build');
        return _fail();
      },
    );
    final probe = await detector.probe(rtkDetect);
    expect(probe.version, isNull);
    expect(probe.satisfiesMinVersion, isTrue);
  });

  test('major version >= 1 always satisfies 0.23.0', () async {
    final detector = ExtensionDetector(
      processRunner: (exe, args, {environment}) async {
        if (args.length == 1 && args.first == 'rtk') return _ok('/usr/bin/rtk');
        if (args.length == 1 && args.first == 'jq') return _ok('/usr/bin/jq');
        if (args.contains('--version')) return _ok('rtk 1.0.0');
        return _fail();
      },
    );
    final probe = await detector.probe(rtkDetect);
    expect(probe.satisfiesMinVersion, isTrue);
  });
}
