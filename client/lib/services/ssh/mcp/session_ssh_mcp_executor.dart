import 'dart:convert';
import 'dart:typed_data';

import 'package:teampilot/models/ssh_profile.dart';
import 'package:teampilot/services/ssh/ssh_client_factory.dart';
import 'package:teampilot/services/ssh/ssh_storage_io.dart';

import 'session_ssh_mcp_operations.dart';

/// [SessionSshMcpExecutor] backed by the shared storage-plane SSH factory.
class SshClientFactorySessionSshMcpExecutor implements SessionSshMcpExecutor {
  SshClientFactorySessionSshMcpExecutor(this._factory);

  final SshClientFactory _factory;

  @override
  Future<({int? exitCode, String stdout, String stderr})> runCommand({
    required SshProfile profile,
    required String command,
    required Duration timeout,
  }) async {
    final result = await _factory.runOnStorage(
      profile,
      command,
      timeout: timeout,
    );
    return (
      exitCode: result.exitCode,
      stdout: utf8.decode(result.stdout, allowMalformed: true),
      stderr: utf8.decode(result.stderr, allowMalformed: true),
    );
  }

  @override
  Future<void> upload({
    required SshProfile profile,
    required List<int> bytes,
    required String remotePath,
  }) async {
    final storage = await _factory.storageFor(profile);
    await storage.writeBytes(
      remotePath,
      Uint8List.fromList(bytes),
      timeout: SshStorageIo.provisionPhaseTimeout,
    );
  }

  @override
  Future<List<int>> download({
    required SshProfile profile,
    required String remotePath,
  }) async {
    final storage = await _factory.storageFor(profile);
    return storage.readBytes(
      remotePath,
      timeout: SshStorageIo.provisionPhaseTimeout,
    );
  }
}
