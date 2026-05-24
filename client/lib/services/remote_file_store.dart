import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:path/path.dart' as p;

import 'io/filesystem.dart';
import 'ssh_client_factory.dart';
import '../models/ssh_profile.dart';

class RemoteDirEntry {
  const RemoteDirEntry({required this.name, required this.isDirectory});

  final String name;
  final bool isDirectory;
}

class RemoteFileStore {
  RemoteFileStore({
    required SshProfile profile,
    required SshClientFactory clientFactory,
  }) : _profile = profile,
       _clientFactory = clientFactory;

  final SshProfile _profile;
  final SshClientFactory _clientFactory;

  Future<SftpClient> _ensureConnected() => _clientFactory.sftpFor(_profile);

  Future<String> expandHome(String path) async {
    if (!path.startsWith('~')) return path;
    if (path == '~' || path == '~/') return '.';
    return path.substring(2);
  }

  Future<FsEntityKind> statKind(String path) async {
    try {
      final sftp = await _ensureConnected();
      final resolved = await expandHome(path);
      final attrs = await sftp.stat(resolved);
      if (attrs.isDirectory) return FsEntityKind.directory;
      if (attrs.isSymbolicLink) return FsEntityKind.symlink;
      return FsEntityKind.file;
    } on SftpStatusError catch (e) {
      if (e.code == SftpStatusCode.noSuchFile) return FsEntityKind.notFound;
      rethrow;
    }
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

  Future<List<int>?> readFileBytes(String path) async {
    try {
      final sftp = await _ensureConnected();
      final resolved = await expandHome(path);
      final file = await sftp.open(resolved, mode: SftpFileOpenMode.read);
      final bytes = await file.readBytes();
      await file.close();
      return bytes;
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
      mode:
          SftpFileOpenMode.write |
          SftpFileOpenMode.create |
          SftpFileOpenMode.truncate,
    );
    await file.writeBytes(bytes);
    await file.close();
  }

  Future<List<String>> listDirectory(String path) async {
    final entries = await listDirectoryEntries(path);
    return entries.map((e) => e.name).toList();
  }

  Future<List<RemoteDirEntry>> listDirectoryEntries(String path) async {
    final sftp = await _ensureConnected();
    final resolved = await expandHome(path);
    final names = await sftp.listdir(resolved);
    return [
      for (final n in names)
        if (n.filename != '.' && n.filename != '..')
          RemoteDirEntry(name: n.filename, isDirectory: n.attr.isDirectory),
    ];
  }

  Future<void> writeBytes(String path, Uint8List bytes) async {
    final sftp = await _ensureConnected();
    final resolved = await expandHome(path);
    final file = await sftp.open(
      resolved,
      mode:
          SftpFileOpenMode.write |
          SftpFileOpenMode.create |
          SftpFileOpenMode.truncate,
    );
    await file.writeBytes(bytes);
    await file.close();
  }

  Future<void> ensureDirectory(String absolutePosixPath) async {
    final client = await _clientFactory.clientFor(_profile);
    final result = await client.runWithResult(
      'mkdir -p -- ${shellSingleQuote(absolutePosixPath)}',
      stderr: false,
    );
    if (result.exitCode != 0) {
      throw StateError(
        'mkdir failed (${result.exitCode}): ${utf8.decode(result.stderr, allowMalformed: true)}',
      );
    }
  }

  Future<void> removeRecursive(String absolutePosixPath) async {
    final client = await _clientFactory.clientFor(_profile);
    await client.runWithResult(
      'rm -rf -- ${shellSingleQuote(absolutePosixPath)}',
      stderr: false,
    );
  }

  Future<void> createSymlink({
    required String target,
    required String linkPath,
  }) async {
    final client = await _clientFactory.clientFor(_profile);
    final parent = p.Context(style: p.Style.posix).dirname(linkPath);
    if (parent.isNotEmpty && parent != '.') {
      await ensureDirectory(parent);
    }
    await removeRecursive(linkPath);
    final result = await client.runWithResult(
      'ln -sf -- ${shellSingleQuote(target)} ${shellSingleQuote(linkPath)}',
      stderr: false,
    );
    if (result.exitCode != 0) {
      throw StateError(
        'ln failed (${result.exitCode}): ${utf8.decode(result.stderr, allowMalformed: true)}',
      );
    }
  }

  static String shellSingleQuote(String value) {
    return "'${value.replaceAll("'", "'\\''")}'";
  }

  /// Uploads a local directory tree to [remoteRoot] on the SSH host.
  Future<void> uploadLocalDirectory({
    required Directory localRoot,
    required String remoteRoot,
  }) async {
    if (!localRoot.existsSync()) {
      throw StateError('local directory missing: ${localRoot.path}');
    }
    final posix = p.Context(style: p.Style.posix);
    await ensureDirectory(remoteRoot);
    await for (final entity in localRoot.list(
      recursive: true,
      followLinks: false,
    )) {
      final rel = p.relative(entity.path, from: localRoot.path);
      final remotePath = rel == '.'
          ? remoteRoot
          : posix.join(remoteRoot, rel.replaceAll(r'\', '/'));
      if (entity is Directory) {
        await ensureDirectory(remotePath);
      } else if (entity is File) {
        await writeBytes(remotePath, await entity.readAsBytes());
      }
    }
  }

  Future<void> movePath(String from, String to) async {
    final posix = p.Context(style: p.Style.posix);
    final parent = posix.dirname(to);
    if (parent.isNotEmpty && parent != '.' && parent != '/') {
      await ensureDirectory(parent);
    }
    await removeRecursive(to);
    final client = await _clientFactory.clientFor(_profile);
    final result = await client.runWithResult(
      'mv -- ${shellSingleQuote(from)} ${shellSingleQuote(to)}',
      stderr: false,
    );
    if (result.exitCode != 0) {
      throw StateError(
        'mv failed (${result.exitCode}): ${utf8.decode(result.stderr, allowMalformed: true)}',
      );
    }
  }

  Future<void> copyTree({
    required String source,
    required String destination,
  }) async {
    final posix = p.Context(style: p.Style.posix);
    final parent = posix.dirname(destination);
    if (parent.isNotEmpty && parent != '.' && parent != '/') {
      await ensureDirectory(parent);
    }
    await removeRecursive(destination);
    await ensureDirectory(destination);
    final client = await _clientFactory.clientFor(_profile);
    final result = await client.runWithResult(
      'cp -R -- ${shellSingleQuote('$source/.')} ${shellSingleQuote(destination)}',
      stderr: false,
    );
    if (result.exitCode != 0) {
      throw StateError(
        'cp failed (${result.exitCode}): ${utf8.decode(result.stderr, allowMalformed: true)}',
      );
    }
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
    _clientFactory.disconnectProfile(_profile.id);
  }
}
