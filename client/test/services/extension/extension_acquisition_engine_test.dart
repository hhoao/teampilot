import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/extension_manifest.dart';
import 'package:teampilot/services/cli/installer_types.dart';
import 'package:teampilot/services/extension/extension_acquisition_engine.dart';
import 'package:teampilot/services/extension/extension_detector.dart';

ExtensionManifest _manifest(Map<String, Object?> acquire) =>
    ExtensionManifest.fromJson({
      'id': 'x',
      'name': 'X',
      'acquire': acquire,
      'detect': {'executable': 'x', 'versionArgs': ['--version']},
    });

extension on ExtensionManifest {
  ExtensionManifest copyForScript(String url) => ExtensionManifest.fromJson({
        'id': id,
        'name': name,
        'acquire': {'kind': 'script', 'package': url, 'binary': 'x'},
        'detect': {'executable': 'x', 'versionArgs': ['--version']},
      });
}

ExtensionDetector _present(String version) => ExtensionDetector(
      processRunner: (exe, args, {environment}) async {
        if (args.length == 1 && args.first == 'x') {
          return ProcessResult(0, 0, '/usr/bin/x', '');
        }
        if (args.contains('--version')) return ProcessResult(0, 0, 'x $version', '');
        return ProcessResult(0, 1, '', '');
      },
    );

void main() {
  test('node-package runs npm install -g', () async {
    final commands = <CliInstallerCommand>[];
    final engine = ExtensionAcquisitionEngine(
      runner: (cmd) async {
        commands.add(cmd);
        return const CliInstallerCommandResult(exitCode: 0);
      },
      detector: _present('1.4.0'),
    );

    final result = await engine.install(
      _manifest({'kind': 'node-package', 'package': '@scope/pkg', 'binary': 'x'}),
    );

    expect(commands.single.executable, 'npm');
    expect(commands.single.arguments, ['install', '-g', '@scope/pkg']);
    expect(result.success, isTrue);
    expect(result.version, '1.4.0');
  });

  test('cargo runs cargo install', () async {
    final commands = <CliInstallerCommand>[];
    final engine = ExtensionAcquisitionEngine(
      runner: (cmd) async {
        commands.add(cmd);
        return const CliInstallerCommandResult(exitCode: 0);
      },
      detector: _present('0.24.0'),
    );

    await engine.install(_manifest({'kind': 'cargo', 'package': 'rtk', 'binary': 'rtk'}));

    expect(commands.single.executable, 'cargo');
    expect(commands.single.arguments, ['install', 'rtk']);
  });

  test('falls back to an alternative when primary fails', () async {
    final commands = <CliInstallerCommand>[];
    final engine = ExtensionAcquisitionEngine(
      runner: (cmd) async {
        commands.add(cmd);
        return CliInstallerCommandResult(exitCode: cmd.executable == 'cargo' ? 1 : 0);
      },
      detector: _present('0.24.0'),
    );

    final result = await engine.install(_manifest({
      'kind': 'cargo',
      'package': 'rtk',
      'binary': 'rtk',
      'alternatives': ['brew:rtk'],
    }));

    expect(commands.map((c) => c.executable), ['cargo', 'brew']);
    expect(commands.last.arguments, ['install', 'rtk']);
    expect(result.success, isTrue);
  });

  test('fails when all commands fail', () async {
    final engine = ExtensionAcquisitionEngine(
      runner: (cmd) async => const CliInstallerCommandResult(exitCode: 1, stderr: 'nope'),
      detector: _present('1.0.0'),
    );
    final result = await engine.install(_manifest({'kind': 'cargo', 'package': 'rtk'}));
    expect(result.success, isFalse);
    expect(result.message, contains('nope'));
  });

  test('fails cleanly when acquire is none/absent', () async {
    final engine = ExtensionAcquisitionEngine(
      runner: (cmd) async => const CliInstallerCommandResult(exitCode: 0),
      detector: _present('1.0.0'),
    );
    final result = await engine.install(ExtensionManifest.fromJson({
      'id': 'x',
      'name': 'X',
      'detect': {'executable': 'x'},
    }));
    expect(result.success, isFalse);
  });

  test('uninstall runs the kind-appropriate command', () async {
    final commands = <CliInstallerCommand>[];
    final engine = ExtensionAcquisitionEngine(
      runner: (cmd) async {
        commands.add(cmd);
        return const CliInstallerCommandResult(exitCode: 0);
      },
      detector: _present('1.0.0'),
    );
    await engine.uninstall(
      _manifest({'kind': 'node-package', 'package': '@scope/pkg', 'binary': 'x'}),
    );
    expect(commands.single.executable, 'npm');
    expect(commands.single.arguments, ['uninstall', '-g', '@scope/pkg']);
  });

  test('script kind accepts an https url', () async {
    final commands = <CliInstallerCommand>[];
    final engine = ExtensionAcquisitionEngine(
      runner: (cmd) async {
        commands.add(cmd);
        return const CliInstallerCommandResult(exitCode: 0);
      },
      detector: _present('1.0.0'),
    );
    await engine.install(_manifest({
      'kind': 'script',
      'binary': 'x',
      'alternatives': <String>[],
    }).copyForScript('https://example.com/install.sh'));
    expect(commands.single.executable, 'sh');
    expect(commands.single.arguments.last, contains('https://example.com/install.sh'));
  });

  test('script kind rejects non-https / metacharacter urls (no command run)', () async {
    final commands = <CliInstallerCommand>[];
    final engine = ExtensionAcquisitionEngine(
      runner: (cmd) async {
        commands.add(cmd);
        return const CliInstallerCommandResult(exitCode: 0);
      },
      detector: _present('1.0.0'),
    );
    final result = await engine.install(_manifest({
      'kind': 'script',
      'binary': 'x',
    }).copyForScript('https://example.com/i.sh; rm -rf /'));
    expect(commands, isEmpty);
    expect(result.success, isFalse);
  });
}
