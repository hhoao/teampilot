import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/cli_binary_kind.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/models/ssh_profile.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/remote_cli_installer.dart';
import 'package:teampilot/services/cli/registry/capabilities/cli_executable_capability.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/remote/remote_cli_readiness.dart';
import 'package:teampilot/services/ssh/ssh_client_factory.dart';
import 'package:teampilot/services/ssh/worker/ssh_worker_member_session.dart';
import 'package:teampilot/services/ssh/worker/ssh_worker_storage_types.dart';

void main() {
  const target = RuntimeTarget(
    id: 'ssh:host-a',
    label: 'host',
    kind: RuntimeKind.ssh,
    sshProfileId: 'host-a',
  );

  late Map<String, String> overrides;
  late RemoteCliReadinessService service;

  RemoteCliReadinessService build({
    required SshCommandRunner run,
    RemoteInstallAction? adapterInstall,
  }) {
    overrides = {};
    return RemoteCliReadinessService(
      registry: CliToolRegistry.builtIn(),
      sshClientFactory: _ThrowingSshClientFactory(),
      profileById: (id) => id == 'host-a'
          ? const SshProfile(
              id: 'host-a',
              name: 'host',
              host: 'host',
              username: 'u',
            )
          : null,
      cliPathOverride: (_, __) async => null,
      setCliPathOverride: (_, __, ___) async {},
      acpAdapterPathOverride: (_, cli) async => overrides[cli],
      setAcpAdapterPathOverride: (_, cli, path) async {
        overrides[cli] = path;
      },
      adapterInstallActionBuilder: adapterInstall == null
          ? null
          : (_, __, ___) => adapterInstall,
      remoteRunnerFor: (_, {required includeStderr}) => run,
    );
  }

  test(
    'probe(adapter) reports ready when the adapter is on the host',
    () async {
      service = build(
        run: (command) async {
          if (command.contains('claude-agent-acp')) {
            return const SshCommandResult(
              exitCode: 0,
              stdout: '/home/u/.local/bin/claude-agent-acp\n',
            );
          }
          return const SshCommandResult(exitCode: 1, stdout: '');
        },
      );

      final result = await service.probe(
        target: target,
        cli: CliTool.claude,
        kind: CliBinaryKind.adapter,
      );

      expect(result, isA<RemoteCliReady>());
      expect(
        (result as RemoteCliReady).path,
        '/home/u/.local/bin/claude-agent-acp',
      );
    },
  );

  test('probe(adapter) reports missing when nothing resolves', () async {
    service = build(
      run: (_) async => const SshCommandResult(exitCode: 1, stdout: ''),
    );

    final result = await service.probe(
      target: target,
      cli: CliTool.claude,
      kind: CliBinaryKind.adapter,
    );

    expect(result, isA<RemoteCliMissing>());
  });

  test('probe(adapter) uses a stored override without probing', () async {
    var probed = false;
    service = build(
      run: (_) async {
        probed = true;
        return const SshCommandResult(exitCode: 1, stdout: '');
      },
    );
    overrides['claude'] = '/opt/claude-agent-acp';

    final result = await service.probe(
      target: target,
      cli: CliTool.claude,
      kind: CliBinaryKind.adapter,
    );

    expect((result as RemoteCliReady).path, '/opt/claude-agent-acp');
    expect(probed, isFalse);
  });

  test('install(adapter) installs and remembers the path', () async {
    var installCalls = 0;
    service = build(
      run: (_) async => const SshCommandResult(exitCode: 1, stdout: ''),
      adapterInstall: ({required run, required onProgress}) async {
        installCalls++;
        return '/home/u/.local/bin/claude-agent-acp';
      },
    );

    final result = await service.install(
      target: target,
      cli: CliTool.claude,
      kind: CliBinaryKind.adapter,
    );

    expect(installCalls, 1);
    expect(
      (result as RemoteCliReady).path,
      '/home/u/.local/bin/claude-agent-acp',
    );
    expect(overrides['claude'], '/home/u/.local/bin/claude-agent-acp');
  });

  test(
    'install(adapter) fails for a CLI without an adapter installer',
    () async {
      service = build(
        run: (_) async => const SshCommandResult(exitCode: 1, stdout: ''),
      );

      final result = await service.install(
        target: target,
        cli: CliTool.cursor,
        kind: CliBinaryKind.adapter,
      );

      expect(result, isA<RemoteCliFailed>());
    },
  );

  test(
    'install(adapter) uses the member task when no runner is injected',
    () async {
      overrides = {};
      final transport = _FakeMemberTransport();
      service = RemoteCliReadinessService(
        registry: CliToolRegistry.builtIn(),
        sshClientFactory: _TaskFactory(transport),
        profileById: (_) => const SshProfile(
          id: 'host-a',
          name: 'host',
          host: 'host',
          username: 'u',
        ),
        cliPathOverride: (_, __) async => null,
        setCliPathOverride: (_, __, ___) async {},
        acpAdapterPathOverride: (_, __) async => null,
        setAcpAdapterPathOverride: (_, __, ___) async {},
      );

      final result = await service.install(
        target: target,
        cli: CliTool.claude,
        kind: CliBinaryKind.adapter,
      );

      expect(result, isA<RemoteCliReady>());
      expect(transport.opened, 1);
      expect(transport.closed, 1);
      expect(transport.commands, isNotEmpty);
    },
  );
}

final class _TaskFactory implements SshClientFactory {
  _TaskFactory(this.transport);
  final SshWorkerMemberTransport transport;

  @override
  Future<SshWorkerMemberTransport> openMemberTransport(
    SshProfile profile, {
    Duration timeout = const Duration(seconds: 10),
  }) async => transport;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

final class _FakeMemberTransport implements SshWorkerMemberTransport {
  var opened = 0;
  var closed = 0;
  final commands = <String>[];

  @override
  Future<void> open(
    SshProfile profile, {
    Duration timeout = const Duration(seconds: 10),
  }) async => opened++;

  @override
  Future<SshWorkerRunResult> run(String command, {bool stderr = true}) async {
    commands.add(command);
    return SshWorkerRunResult(
      stdout: Uint8List.fromList(
        '/home/u/.local/bin/claude-agent-acp\n'.codeUnits,
      ),
      stderr: Uint8List(0),
      exitCode: 0,
    );
  }

  @override
  Future<SshWorkerExecChannel> startProcess(String command) =>
      throw UnimplementedError();

  @override
  Future<SshWorkerPtyChannel> openPty({
    String? command,
    required int columns,
    required int rows,
    Map<String, String>? environment,
  }) => throw UnimplementedError();

  @override
  Future<void> close() async => closed++;
}

class _ThrowingSshClientFactory implements SshClientFactory {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
