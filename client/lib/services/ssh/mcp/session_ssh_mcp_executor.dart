import 'dart:convert';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:teampilot/models/ssh_profile.dart';
import 'package:teampilot/services/ssh/ssh_client_factory.dart';

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
    final sftp = await _factory.sftpFor(profile);
    final file = await sftp.open(
      remotePath,
      mode:
          SftpFileOpenMode.write |
          SftpFileOpenMode.create |
          SftpFileOpenMode.truncate,
    );
    await file.writeBytes(Uint8List.fromList(bytes));
    await file.close();
  }

  @override
  Future<List<int>> download({
    required SshProfile profile,
    required String remotePath,
  }) async {
    final sftp = await _factory.sftpFor(profile);
    final file = await sftp.open(remotePath, mode: SftpFileOpenMode.read);
    final bytes = await file.readBytes();
    await file.close();
    return bytes;
  }
}
