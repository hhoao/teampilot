import 'dart:io';

import 'package:dartssh2/dartssh2.dart';
import 'package:path/path.dart' as p;

/// Spins up [test/integration/docker/Dockerfile] for real SSH integration tests.
///
/// Requires Docker CLI + daemon. Run tests from `client/`:
/// `flutter test test/integration/remote_cli_install_docker_test.dart --tags integration`
class DockerSshServer {
  DockerSshServer._({
    required this.containerName,
    required this.host,
    required this.port,
    required this.sshUsername,
    required this.sshPassword,
  });

  static const imageTag = 'teampilot-it-ssh:latest';

  /// Prebuilt Node + Claude for mixed-team IT (skips per-run npm bootstrap).
  static const mixedImageTag = 'teampilot-it-ssh-mixed:latest';

  static const defaultUsername = 'testuser';
  static const defaultPassword = 'teampilot-test';

  /// Hostname containers use to reach services bound on the test runner host.
  static const hostGatewayHostname = 'host.docker.internal';

  final String containerName;
  final String host;
  final int port;
  final String sshUsername;
  final String sshPassword;

  static Future<bool> isDockerAvailable() async {
    try {
      final result = await Process.run('docker', [
        'version',
        '--format',
        '{{.Server.Version}}',
      ]);
      return result.exitCode == 0 && '${result.stdout}'.trim().isNotEmpty;
    } on ProcessException {
      return false;
    }
  }

  static String dockerContextDir(String clientRoot) =>
      p.join(clientRoot, 'test', 'integration', 'docker');

  static Future<DockerSshServer> start({
    String clientRoot = '.',
    String dockerfileName = 'Dockerfile',
    String imageTag = DockerSshServer.imageTag,
  }) async {
    if (!await isDockerAvailable()) {
      throw StateError('Docker is not available');
    }

    final contextDir = dockerContextDir(clientRoot);
    final dockerfile = File(p.join(contextDir, dockerfileName));
    if (!dockerfile.existsSync()) {
      throw StateError('Missing Dockerfile at ${dockerfile.path}');
    }

    final build = await Process.run('docker', [
      'build',
      '-t',
      imageTag,
      '-f',
      dockerfile.path,
      contextDir,
    ]);
    if (build.exitCode != 0) {
      throw StateError(
        'docker build failed (exit ${build.exitCode}):\n'
        '${build.stdout}\n${build.stderr}',
      );
    }

    final name = 'teampilot-it-ssh-${DateTime.now().microsecondsSinceEpoch}';
    final run = await Process.run('docker', [
      'run',
      '--rm',
      '-d',
      '--name',
      name,
      '--add-host=host.docker.internal:host-gateway',
      '-p',
      '127.0.0.1::22',
      imageTag,
    ]);
    if (run.exitCode != 0) {
      throw StateError(
        'docker run failed (exit ${run.exitCode}):\n'
        '${run.stdout}\n${run.stderr}',
      );
    }

    final mappedPort = await _readMappedPort(name);
    final server = DockerSshServer._(
      containerName: name,
      host: '127.0.0.1',
      port: mappedPort,
      sshUsername: defaultUsername,
      sshPassword: defaultPassword,
    );
    await server.waitUntilReady();
    return server;
  }

  /// Mixed-team IT image: SSH + Node + global `claude` under `~/.local/bin`.
  static Future<DockerSshServer> startMixed({String clientRoot = '.'}) =>
      start(
        clientRoot: clientRoot,
        dockerfileName: 'Dockerfile.mixed',
        imageTag: mixedImageTag,
      );

  static Future<int> _readMappedPort(String containerName) async {
    final port = await Process.run('docker', ['port', containerName, '22']);
    if (port.exitCode != 0) {
      throw StateError(
        'docker port failed (exit ${port.exitCode}):\n'
        '${port.stdout}\n${port.stderr}',
      );
    }
    final line = '${port.stdout}'.trim().split('\n').first.trim();
    final match = RegExp(r':(\d+)$').firstMatch(line);
    if (match == null) {
      throw StateError('Could not parse mapped port from "$line"');
    }
    return int.parse(match.group(1)!);
  }

  Future<void> waitUntilReady({
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      try {
        final socket = await SSHSocket.connect(
          host,
          port,
          timeout: const Duration(seconds: 2),
        );
        socket.close();
        return;
      } on Object {
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
    }
    throw StateError('SSH on $host:$port not ready within $timeout');
  }

  Future<void> stop() async {
    await Process.run('docker', ['rm', '-f', containerName]);
  }
}
