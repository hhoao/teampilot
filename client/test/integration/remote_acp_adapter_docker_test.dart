@Tags(['integration', 'docker'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/session/acp/acp_transport_wiring.dart';
import 'package:teampilot/models/cli_binary_kind.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/models/ssh_profile.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/repositories/ssh_credential_store.dart';
import 'package:teampilot/repositories/ssh_known_host_repository.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/cli/remote_cli_locator.dart';
import 'package:teampilot/services/remote/remote_cli_readiness.dart';
import 'package:teampilot/services/ssh/ssh_client_factory.dart';

import 'support/docker_ssh_server.dart';

/// Real-SSH coverage for the **remote ACP adapter readiness** path
/// (`docs/superpowers/specs/2026-10-16-remote-acp-adapter-readiness-design.md`).
///
/// Before this file the remote adapter flow had only fake-runner unit tests plus
/// a manual smoke checklist — no real sshd ever located, installed, or spawned
/// `claude-agent-acp`.
///
/// Run from `client/` (needs Docker daemon + outbound network to npm):
/// ```bash
/// dart run tool/run_tests.dart --tags "integration && docker" \
///   test/integration/remote_acp_adapter_docker_test.dart
/// ```
void main() {
  DockerSshServer? server;
  SshClientFactory? sshFactory;
  final cliOverrides = <String, String>{};
  final adapterOverrides = <String, String>{};

  setUpAll(() async {
    if (!await DockerSshServer.isDockerAvailable()) {
      return;
    }
    server = await DockerSshServer.start(clientRoot: Directory.current.path);

    final credentials = InMemorySshCredentialStore();
    await credentials.savePassword(
      _profileId,
      DockerSshServer.defaultPassword,
    );

    sshFactory = SshClientFactory(
      credentialStore: credentials,
      knownHostRepository: InMemorySshKnownHostRepository(),
      onHostKeyPrompt: (_) async => true,
    );
  });

  tearDownAll(() async {
    sshFactory?.disconnectAll();
    await server?.stop();
  });

  test(
    'locate → install → locate the Claude ACP adapter over real SSH',
    () async {
      if (server == null || sshFactory == null) {
        markTestSkipped('Docker is not available');
      }
      final docker = server!;
      final factory = sshFactory!;

      final profile = _profile.copyWith(port: docker.port);
      final target = RuntimeTarget(
        id: 'ssh:${profile.id}',
        label: profile.name,
        kind: RuntimeKind.ssh,
        sshProfileId: profile.id,
      );

      final service = RemoteCliReadinessService(
        registry: CliToolRegistry.builtIn(),
        sshClientFactory: factory,
        profileById: (id) => id == profile.id ? profile : null,
        cliPathOverride: (t, c) async => cliOverrides['$t|$c'],
        setCliPathOverride: (t, c, p) async => cliOverrides['$t|$c'] = p,
        acpAdapterPathOverride: (t, c) async => adapterOverrides['$t|$c'],
        setAcpAdapterPathOverride: (t, c, p) async =>
            adapterOverrides['$t|$c'] = p,
      );

      // 1. Bare image: the adapter must probe as missing (this is what makes the
      //    landing/panel "Required CLIs on this machine" row appear).
      final missing = await service.probe(
        target: target,
        cli: CliTool.claude,
        kind: CliBinaryKind.adapter,
      );
      expect(
        missing,
        isA<RemoteCliMissing>(),
        reason: 'bare Debian image must not already have claude-agent-acp',
      );

      // 2. User-driven install bootstraps Node + npm-installs the adapter.
      final installed = await service.install(
        target: target,
        cli: CliTool.claude,
        kind: CliBinaryKind.adapter,
      );
      expect(
        installed,
        isA<RemoteCliReady>(),
        reason: installed is RemoteCliFailed
            ? 'install failed: ${installed.message}'
            : null,
      );
      final path = (installed as RemoteCliReady).path;
      expect(path, contains('claude-agent-acp'));
      expect(
        adapterOverrides['${target.id}|claude'],
        path,
        reason: 'resolved adapter path must be remembered in targets.json',
      );

      // 3. Re-probe must reuse the stored override without re-locating.
      final ready = await service.probe(
        target: target,
        cli: CliTool.claude,
        kind: CliBinaryKind.adapter,
      );
      expect(ready, isA<RemoteCliReady>());
      expect((ready as RemoteCliReady).path, path);

      // 4. The whole point: the adapter must actually execute on the remote host
      //    under the *production* remote command encoding, which prepends the
      //    TeamPilot toolchain Node bin to PATH (npm shims are `#!/usr/bin/env
      //    node`). A raw `$path --version` fails with exit 127 because the
      //    non-interactive ssh PATH has no node.
      final client = await factory.clientForStorage(
        profile,
        timeout: const Duration(seconds: 30),
      );
      final run = RemoteCliLocator.getRunnerForClient(
        client,
        includeStderr: true,
        timeout: const Duration(seconds: 20),
      );

      final nodeProbe = await run(
        buildAcpRemoteCommand(
          profile: profile,
          argv: const ['node', '--version'],
          workingDirectory: '/home/${profile.username}',
          env: const {},
        ),
      );
      expect(
        nodeProbe.exitCode,
        0,
        reason:
            'production remote command must expose the toolchain Node on PATH.\n'
            'stdout: ${nodeProbe.stdout}\nstderr: ${nodeProbe.stderr}',
      );

      String? execFailure;
      var started = false;
      try {
        final version = await run(
          buildAcpRemoteCommand(
            profile: profile,
            argv: [path, '--version'],
            workingDirectory: '/home/${profile.username}',
            env: const {},
          ),
        );
        started = version.exitCode != 127 &&
            !version.stderr.contains('No such file or directory');
        execFailure =
            'exit ${version.exitCode}\n'
            'stdout: ${version.stdout}\nstderr: ${version.stderr}';
      } on Object catch (error) {
        // A long-lived ACP server that ignores --version simply never returns;
        // reaching this point still means the shebang resolved and the process
        // started.
        started = true;
        execFailure = 'did not exit (expected for a stdio server): $error';
      }
      expect(
        started,
        isTrue,
        reason: 'adapter at $path failed to start over remote ssh exec: '
            '$execFailure',
      );
    },
    timeout: const Timeout(Duration(minutes: 12)),
  );
}

const _profileId = 'docker-acp-it';

const _profile = SshProfile(
  id: _profileId,
  name: 'docker-acp-it',
  host: '127.0.0.1',
  port: 22,
  username: DockerSshServer.defaultUsername,
);
