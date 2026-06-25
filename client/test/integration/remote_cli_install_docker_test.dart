@Tags(['integration'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/ssh_profile.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/repositories/ssh_credential_store.dart';
import 'package:teampilot/repositories/ssh_known_host_repository.dart';
import 'package:teampilot/services/cli/remote_cli_installer.dart';
import 'package:teampilot/services/cli/remote_cli_locator.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/remote/remote_preflight_cli_install.dart';
import 'package:teampilot/services/ssh/ssh_client_factory.dart';

import 'support/docker_ssh_server.dart';

/// Real SSH + Node bootstrap + `npm install -g` over Docker.
///
/// Run from `client/` (needs Docker daemon + outbound network to nodejs.org/npm):
/// ```bash
/// flutter test test/integration/remote_cli_install_docker_test.dart --tags integration
/// ```
void main() {
  DockerSshServer? server;
  SshClientFactory? sshFactory;

  setUpAll(() async {
    if (!await DockerSshServer.isDockerAvailable()) {
      return;
    }
    server = await DockerSshServer.start(
      clientRoot: Directory.current.path,
    );

    final credentials = InMemorySshCredentialStore();
    await credentials.savePassword(
      _profile.id,
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
    'RemoteCliInstaller bootstraps Node and installs claude over real SSH',
    () async {
      if (server == null || sshFactory == null) {
        markTestSkipped('Docker is not available');
      }
      final docker = server!;
      final factory = sshFactory!;

      final profile = _profile.copyWith(port: docker.port);
      final client = await factory.clientFor(
        profile,
        timeout: const Duration(seconds: 30),
      );
      final run = RemoteCliLocator.runnerForClient(client);

      final install = buildRemotePreflightCliInstall(
        registry: CliToolRegistry.builtIn(),
        profile: profile,
        cli: CliTool.claude,
      );

      final progress = <String>[];
      final installer = RemoteCliInstaller();
      final path = await installer.ensure(
        cli: CliTool.claude,
        run: run,
        optIn: true,
        supportsInstaller: true,
        onProgress: progress.add,
        install: ({required run, required onProgress}) => install(
          run: run,
          onProgress: onProgress,
        ),
      );

      expect(path, isNotEmpty);
      expect(path, contains('claude'));
      expect(
        progress,
        anyElement(startsWith('Bootstrapping Node.js')),
        reason: 'expected Node bootstrap on a bare image',
      );
      expect(
        progress,
        anyElement(contains('Claude Code')),
        reason: 'expected npm global install progress',
      );

      final version = await run('$path --version');
      expect(version.exitCode, 0);
      expect(version.stdout.trim(), isNotEmpty);
    },
    timeout: const Timeout(Duration(minutes: 12)),
  );
}

const _profile = SshProfile(
  id: 'docker-it',
  name: 'docker-it',
  host: '127.0.0.1',
  port: 22,
  username: DockerSshServer.defaultUsername,
);
