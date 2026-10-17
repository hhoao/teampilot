import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/cli_binary_kind.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/models/ssh_profile.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/installer_types.dart';
import 'package:teampilot/services/cli/remote_cli_installer.dart';
import 'package:teampilot/services/cli/registry/capabilities/cli_executable_capability.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/remote/remote_cli_readiness.dart';
import 'package:teampilot/services/ssh/ssh_client_factory.dart';

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

  test('probe(adapter) reports ready when the adapter is on the host', () async {
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
  });

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
}

class _ThrowingSshClientFactory implements SshClientFactory {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
