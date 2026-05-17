import 'dart:convert';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

import 'ssh_client_factory.dart';
import '../models/ssh_profile.dart';

class RemoteFileStore {
  RemoteFileStore({
    required SshProfile profile,
    required SshClientFactory clientFactory,
  })  : _profile = profile,
        _clientFactory = clientFactory;

  final SshProfile _profile;
  final SshClientFactory _clientFactory;

  SSHClient? _client;
  SftpClient? _sftp;

  Future<SftpClient> _ensureConnected() async {
    if (_sftp != null) {
      try {
        await _sftp!.absolute('.');
        return _sftp!;
      } on Object {
        _sftp = null;
        _client?.close();
        _client = null;
      }
    }

    _client = await _clientFactory.createClient(_profile);
    _sftp = await _client!.sftp();
    return _sftp!;
  }

  Future<String> expandHome(String path) async {
    if (!path.startsWith('~')) return path;
    if (path == '~' || path == '~/') return '.';
    return path.substring(2);
  }

  Future<bool> fileExists(String path) async {
    try {
      final sftp = await _ensureConnected();
      final resolved = await expandHome(path);
      await sftp.stat(resolved);
      return true;
    } on SftpStatusError catch (e) {
      if (e.code == SftpStatusCode.noSuchFile) return false;
      rethrow;
    }
  }

  Future<String?> readFile(String path) async {
    try {
      final sftp = await _ensureConnected();
      final resolved = await expandHome(path);
      final file = await sftp.open(resolved, mode: SftpFileOpenMode.read);
      final bytes = await file.readBytes();
      await file.close();
      return utf8.decode(bytes);
    } on SftpStatusError catch (e) {
      if (e.code == SftpStatusCode.noSuchFile) return null;
      rethrow;
    }
  }

  Future<void> writeFile(String path, String contents) async {
    final sftp = await _ensureConnected();
    final resolved = await expandHome(path);
    final bytes = Uint8List.fromList(utf8.encode(contents));
    final file = await sftp.open(
      resolved,
      mode: SftpFileOpenMode.write |
          SftpFileOpenMode.create |
          SftpFileOpenMode.truncate,
    );
    await file.writeBytes(bytes);
    await file.close();
  }

  Future<List<String>> listDirectory(String path) async {
    final sftp = await _ensureConnected();
    final resolved = await expandHome(path);
    final names = await sftp.listdir(resolved);
    return names.map((n) => n.filename).toList();
  }

  Future<void> createDirectory(String path) async {
    final sftp = await _ensureConnected();
    final resolved = await expandHome(path);
    try {
      await sftp.mkdir(resolved);
    } on SftpStatusError catch (_) {
      // Directory might already exist; ignore errors
    }
  }

  Future<void> deleteFile(String path) async {
    final sftp = await _ensureConnected();
    final resolved = await expandHome(path);
    try {
      await sftp.remove(resolved);
    } on SftpStatusError catch (e) {
      if (e.code == SftpStatusCode.noSuchFile) return;
      rethrow;
    }
  }

  Future<void> disconnect() async {
    _sftp = null;
    _client?.close();
    _client = null;
  }
}
