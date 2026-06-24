import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/cli/registry/capabilities/bus_transport_capability.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/team_bus/remote/relay_provisioner.dart';

void main() {
  group('BusTransportCapability per CLI', () {
    final registry = CliToolRegistry.builtIn();

    test('long-blocking CLIs are true, cursor (doorbell) is false', () {
      bool blocking(CliTool cli) =>
          registry.capability<BusTransportCapability>(cli)!.longBlockingWaitForMessage;

      expect(blocking(CliTool.claude), isTrue);
      expect(blocking(CliTool.flashskyai), isTrue);
      expect(blocking(CliTool.codex), isTrue);
      expect(blocking(CliTool.opencode), isTrue);
      expect(blocking(CliTool.cursor), isFalse);
    });
  });

  group('RelayProvisioner', () {
    late Directory tmp;
    late LocalFilesystem fs;
    const provisioner = RelayProvisioner();

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('relay_prov_');
      fs = LocalFilesystem();
    });
    tearDown(() {
      tmp.deleteSync(recursive: true);
      // The bundled-relay path is relative (= remote home under SFTP); under the
      // local test fs it lands in cwd — clean it up.
      final stray =
          Directory(RelayProvisioner.bundledRelayDir.split('/').first);
      if (stray.existsSync()) stray.deleteSync(recursive: true);
    });

    Future<RelayPlan> provision({
      required Future<String> Function(String) run,
      String arch = 'linux-x64',
    }) =>
        provisioner.provision(
          remoteFs: fs,
          run: run,
          tunnelPort: 5599,
          token: 'tok123',
          memberId: 'worker',
          arch: arch,
        );

    test('prefers socat when present, injects handshake + tunnel port', () async {
      final plan = await provision(
        run: (cmd) async => cmd.contains('socat') ? '/usr/bin/socat' : '',
      );
      expect(plan.kind, RelayKind.socat);
      final joined = plan.argv.join(' ');
      expect(joined, contains('/usr/bin/socat'));
      expect(joined, contains('TCP:127.0.0.1:5599'));
      expect(joined, contains('tok123'));
      expect(joined, contains('worker'));
    });

    test('falls back to nc when socat absent', () async {
      final plan = await provision(
        run: (cmd) async => cmd.contains(' nc') ? '/bin/nc' : '',
      );
      expect(plan.kind, RelayKind.nc);
      expect(plan.argv.join(' '), contains('/bin/nc 127.0.0.1 5599'));
    });

    test('posix: materializes bundled static relay via asset resolver + chmod',
        () async {
      final runCmds = <String>[];
      final p = RelayProvisioner(assetResolver: (_) async => const [1, 2, 3]);
      final plan = await p.provision(
        remoteFs: fs,
        run: (cmd) async {
          runCmds.add(cmd);
          return '';
        },
        tunnelPort: 5599,
        token: 'tok123',
        memberId: 'worker',
        arch: 'linux-x64',
      );
      expect(plan.kind, RelayKind.bundledStatic);
      expect(plan.argv.first, contains('flashskyai-bus-relay-linux-x64'));
      expect(plan.argv.first, isNot(contains('.exe')));
      expect(plan.argv, containsAll(['--token', 'tok123', '--member', 'worker']));
      expect(runCmds.any((c) => c.startsWith('chmod +x')), isTrue);
      expect(await fs.readBytes(plan.argv.first), const [1, 2, 3]);
    });

    test('posix: supported arch but no packaged binary → asset-missing error',
        () async {
      expect(
        () => provision(run: (_) async => ''),
        throwsA(isA<RelayAssetMissingException>()),
      );
    });

    test('posix: unsupported arch with no socat/nc → unavailable', () async {
      expect(
        () => RelayProvisioner(assetResolver: (_) async => const [1])
            .provision(
          remoteFs: fs,
          run: (_) async => '',
          tunnelPort: 1,
          token: 't',
          memberId: 'm',
          arch: 'solaris-sparc',
        ),
        throwsA(isA<RelayUnavailableException>()),
      );
    });

    test('windows: bundled .exe relay, no socat/nc probe, no chmod', () async {
      final runCmds = <String>[];
      final p = RelayProvisioner(assetResolver: (_) async => const [9]);
      final plan = await p.provision(
        remoteFs: fs,
        run: (cmd) async {
          runCmds.add(cmd);
          return '';
        },
        tunnelPort: 5599,
        token: 'tok',
        memberId: 'w',
        arch: 'windows-x64',
        remoteOs: RemoteOs.windows,
      );
      expect(plan.kind, RelayKind.bundledStatic);
      expect(plan.argv.first, contains('flashskyai-bus-relay-windows-x64.exe'));
      expect(runCmds.any((c) => c.contains('command -v')), isFalse);
      expect(runCmds.any((c) => c.startsWith('chmod')), isFalse);
    });

    test('windows: no packaged binary → clear asset-missing error', () async {
      expect(
        () => const RelayProvisioner().provision(
          remoteFs: fs,
          run: (_) async => '',
          tunnelPort: 1,
          token: 't',
          memberId: 'm',
          arch: 'windows-x64',
          remoteOs: RemoteOs.windows,
        ),
        throwsA(isA<RelayAssetMissingException>()),
      );
    });

    test('windows: unsupported arch → unavailable', () async {
      expect(
        () => RelayProvisioner(assetResolver: (_) async => const [1])
            .provision(
          remoteFs: fs,
          run: (_) async => '',
          tunnelPort: 1,
          token: 't',
          memberId: 'm',
          arch: 'windows-ia64',
          remoteOs: RemoteOs.windows,
        ),
        throwsA(isA<RelayUnavailableException>()),
      );
    });
  });
}
