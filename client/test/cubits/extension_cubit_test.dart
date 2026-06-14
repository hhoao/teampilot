import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/extension_cubit.dart';
import 'package:teampilot/repositories/extension_repository.dart';
import 'package:teampilot/services/extension/builtin_manifests.dart';
import 'package:teampilot/services/extension/extension_acquisition_engine.dart';
import 'package:teampilot/services/extension/extension_detector.dart';
import 'package:teampilot/services/cli/installer_types.dart';

import '../support/in_memory_filesystem.dart';

ExtensionRepository _repo(InMemoryFilesystem fs) => ExtensionRepository(
      fs: fs,
      stateFilePath: '/root/extensions/state.json',
      manifests: builtInExtensionManifests(),
    );

ExtensionDetector _detector() => ExtensionDetector(
      processRunner: (exe, args, {environment}) async {
        if (args.length == 1 && (args.first == 'rtk' || args.first == 'jq')) {
          return ProcessResult(0, 0, '/usr/bin/${args.first}', '');
        }
        if (args.length == 1 && args.first == 'codegraph') {
          return ProcessResult(0, 1, '', '');
        }
        if (args.contains('--version')) return ProcessResult(0, 0, 'rtk 0.24.0', '');
        return ProcessResult(0, 1, '', '');
      },
    );

void main() {
  test('load derives a row per built-in manifest with status', () async {
    final cubit = ExtensionCubit(
      _repo(InMemoryFilesystem()),
      ExtensionAcquisitionEngine(runner: (c) async => const CliInstallerCommandResult(exitCode: 0)),
      detector: _detector(),
    );

    await cubit.load();

    expect(cubit.state.status, ExtensionLoadStatus.ready);
    final rtk = cubit.state.rows.firstWhere((r) => r.id == 'rtk');
    final cg = cubit.state.rows.firstWhere((r) => r.id == 'codegraph');
    expect(rtk.status, ExtensionStatusCode.ready);
    expect(rtk.version, '0.24.0');
    expect(rtk.globalEnabled, isFalse);
    expect(cg.status, ExtensionStatusCode.notInstalled);
  });

  test('setGlobalEnabled persists and updates the row', () async {
    final fs = InMemoryFilesystem();
    final cubit = ExtensionCubit(
      _repo(fs),
      ExtensionAcquisitionEngine(runner: (c) async => const CliInstallerCommandResult(exitCode: 0)),
      detector: _detector(),
    );
    await cubit.load();

    await cubit.setGlobalEnabled('rtk', true);

    expect(cubit.state.rows.firstWhere((r) => r.id == 'rtk').globalEnabled, isTrue);
    expect((await _repo(fs).load()).globalEnabled, contains('rtk'));
  });

  test('install records installed state and clears busy', () async {
    final fs = InMemoryFilesystem();
    var codegraphInstalled = false;
    final detector = ExtensionDetector(
      processRunner: (exe, args, {environment}) async {
        if (args.length == 1 && args.first == 'codegraph') {
          return codegraphInstalled
              ? ProcessResult(0, 0, '/usr/bin/codegraph', '')
              : ProcessResult(0, 1, '', '');
        }
        if (args.contains('--version')) return ProcessResult(0, 0, 'codegraph 1.4.0', '');
        return ProcessResult(0, 1, '', '');
      },
    );
    final cubit = ExtensionCubit(
      _repo(fs),
      ExtensionAcquisitionEngine(
        runner: (c) async {
          codegraphInstalled = true;
          return const CliInstallerCommandResult(exitCode: 0);
        },
        detector: detector,
      ),
      detector: detector,
    );
    await cubit.load();

    await cubit.install('codegraph');

    expect(cubit.state.busyIds, isEmpty);
    expect((await _repo(fs).load()).installed.containsKey('codegraph'), isTrue);
    expect(cubit.state.rows.firstWhere((r) => r.id == 'codegraph').status, ExtensionStatusCode.ready);
  });

  test('teamOverrides reads only the requested team map', () async {
    final fs = InMemoryFilesystem();
    final cubit = ExtensionCubit(
      _repo(fs),
      ExtensionAcquisitionEngine(runner: (c) async => const CliInstallerCommandResult(exitCode: 0)),
      detector: _detector(),
    );

    await cubit.setTeamOverride('team-a', 'codegraph', true);
    await cubit.setTeamOverride('team-a', 'rtk', false);

    final a = await cubit.teamOverrides('team-a');
    expect(a, {'codegraph': true, 'rtk': false});
    expect(await cubit.teamOverrides('team-b'), isEmpty);
  });

  test('load skips host probe when already ready', () async {
    var probeCalls = 0;
    final detector = ExtensionDetector(
      processRunner: (exe, args, {environment}) async {
        probeCalls++;
        if (args.length == 1 && (args.first == 'rtk' || args.first == 'jq')) {
          return ProcessResult(0, 0, '/usr/bin/${args.first}', '');
        }
        if (args.contains('--version')) return ProcessResult(0, 0, 'rtk 0.24.0', '');
        return ProcessResult(0, 1, '', '');
      },
    );
    final cubit = ExtensionCubit(
      _repo(InMemoryFilesystem()),
      ExtensionAcquisitionEngine(runner: (c) async => const CliInstallerCommandResult(exitCode: 0)),
      detector: detector,
    );

    await cubit.load();
    final afterFirst = probeCalls;
    expect(afterFirst, greaterThan(0));

    await cubit.load();
    expect(probeCalls, afterFirst);
  });

  test('load(force: true) re-probes the host', () async {
    var probeCalls = 0;
    final detector = ExtensionDetector(
      processRunner: (exe, args, {environment}) async {
        probeCalls++;
        if (args.length == 1 && (args.first == 'rtk' || args.first == 'jq')) {
          return ProcessResult(0, 0, '/usr/bin/${args.first}', '');
        }
        if (args.contains('--version')) return ProcessResult(0, 0, 'rtk 0.24.0', '');
        return ProcessResult(0, 1, '', '');
      },
    );
    final cubit = ExtensionCubit(
      _repo(InMemoryFilesystem()),
      ExtensionAcquisitionEngine(runner: (c) async => const CliInstallerCommandResult(exitCode: 0)),
      detector: detector,
    );

    await cubit.load();
    final afterFirst = probeCalls;

    await cubit.load(force: true);
    expect(probeCalls, greaterThan(afterFirst));
  });

  test('dependency-missing row carries the missing requirement names', () async {
    // rtk present, jq absent.
    final detector = ExtensionDetector(
      processRunner: (exe, args, {environment}) async {
        if (args.length == 1 && args.first == 'rtk') {
          return ProcessResult(0, 0, '/usr/bin/rtk', '');
        }
        if (args.contains('--version')) {
          return ProcessResult(0, 0, 'rtk 0.24.0', '');
        }
        return ProcessResult(0, 1, '', '');
      },
    );
    final cubit = ExtensionCubit(
      _repo(InMemoryFilesystem()),
      ExtensionAcquisitionEngine(
          runner: (c) async => const CliInstallerCommandResult(exitCode: 0)),
      detector: detector,
    );

    await cubit.load();

    final rtk = cubit.state.rows.firstWhere((r) => r.id == 'rtk');
    expect(rtk.status, ExtensionStatusCode.dependencyMissing);
    expect(rtk.missingRequirements, ['jq']);
  });

  test('recheck re-probes a single row after a dependency appears', () async {
    var jqPresent = false;
    final detector = ExtensionDetector(
      processRunner: (exe, args, {environment}) async {
        if (args.length == 1 && args.first == 'rtk') {
          return ProcessResult(0, 0, '/usr/bin/rtk', '');
        }
        if (args.length == 1 && args.first == 'jq') {
          return jqPresent
              ? ProcessResult(0, 0, '/usr/bin/jq', '')
              : ProcessResult(0, 1, '', '');
        }
        if (args.contains('--version')) {
          return ProcessResult(0, 0, 'rtk 0.24.0', '');
        }
        return ProcessResult(0, 1, '', '');
      },
    );
    final cubit = ExtensionCubit(
      _repo(InMemoryFilesystem()),
      ExtensionAcquisitionEngine(
          runner: (c) async => const CliInstallerCommandResult(exitCode: 0)),
      detector: detector,
    );
    await cubit.load();
    expect(
      cubit.state.rows.firstWhere((r) => r.id == 'rtk').status,
      ExtensionStatusCode.dependencyMissing,
    );

    jqPresent = true;
    await cubit.recheck('rtk');

    final rtk = cubit.state.rows.firstWhere((r) => r.id == 'rtk');
    expect(rtk.status, ExtensionStatusCode.ready);
    expect(rtk.missingRequirements, isEmpty);
    expect(cubit.state.busyIds, isEmpty);
  });

  test('setTeamOverride(null) clears the override', () async {
    final fs = InMemoryFilesystem();
    final cubit = ExtensionCubit(
      _repo(fs),
      ExtensionAcquisitionEngine(runner: (c) async => const CliInstallerCommandResult(exitCode: 0)),
      detector: _detector(),
    );
    await cubit.setTeamOverride('team-a', 'codegraph', true);
    await cubit.setTeamOverride('team-a', 'codegraph', null);
    expect(await cubit.teamOverrides('team-a'), isEmpty);
  });
}
