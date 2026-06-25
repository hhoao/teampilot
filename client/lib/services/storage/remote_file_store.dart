import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:dartssh2/dartssh2.dart';
import 'package:path/path.dart' as p;

import '../io/filesystem.dart';
import '../ssh/ssh_client_factory.dart';
import '../ssh/ssh_run_result.dart';
import '../../models/runtime_target.dart';
import '../../models/ssh_profile.dart';
import 'remote_home_resolver.dart';

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
  String? _cachedRemoteHome;

  Future<String> _remoteHome() async {
    final cached = _cachedRemoteHome;
    if (cached != null && cached.isNotEmpty) return cached;
    final home = await RemoteHomeResolver(
      clientFactory: _clientFactory,
    ).resolve(_profile);
    if (home == null || home.isEmpty) {
      throw StateError(
        'Failed to resolve remote HOME for ${_profile.hostIdentifier}.',
      );
    }
    _cachedRemoteHome = home;
    return home;
  }

  Future<SftpClient> _ensureConnected() => _clientFactory.sftpFor(_profile);

  Future<String> expandHome(String path) async {
    if (!path.startsWith('~')) return path;
    final home = await _remoteHome();
    if (path == '~' || path == '~/') return home;
    final rest = path.startsWith('~/') ? path.substring(2) : path.substring(1);
    if (rest.isEmpty) return home;
    return p.posix.join(home, rest);
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

  /// Reads the immediate target of a symlink, or null if not a link / missing.
  Future<String?> readlink(String path) async {
    try {
      final sftp = await _ensureConnected();
      final resolved = await expandHome(path);
      return await sftp.readlink(resolved);
    } on SftpStatusError {
      return null;
    }
  }

  /// Fully resolves [path] to its canonical absolute path, or null on failure.
  Future<String?> realpath(String path) async {
    try {
      final sftp = await _ensureConnected();
      final resolved = await expandHome(path);
      return await sftp.absolute(resolved);
    } on SftpStatusError {
      return null;
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
    await _ensureParentDirs(resolved);
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
    await _ensureParentDirs(resolved);
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

  Future<void> ensureDirectory(String path) async {
    final resolved = await expandHome(path);
    if (resolved.isEmpty || resolved == '.' || resolved == '/') return;
    if ((await statKind(resolved)) == FsEntityKind.directory) return;

    final client = await _clientFactory.clientFor(_profile);
    final result = await client.runWithResult(
      'mkdir -p -- ${shellSingleQuote(resolved)}',
      stderr: false,
    );
    if (sshRunSucceeded(result)) return;

    await _ensureDirectorySftp(resolved);
    if ((await statKind(resolved)) == FsEntityKind.directory) return;

    throw StateError(
      'mkdir failed (${sshRunFailureLabel(result)}): '
      '${sshRunOutputDetail(result)}',
    );
  }

  Future<void> _ensureDirectorySftp(String absolutePosixPath) async {
    final sftp = await _ensureConnected();
    final posix = p.posix;
    final isAbsolute = posix.isAbsolute(absolutePosixPath);
    final parts = absolutePosixPath
        .split('/')
        .where((segment) => segment.isNotEmpty);
    var current = isAbsolute ? '/' : '';
    for (final part in parts) {
      current = current.isEmpty
          ? part
          : (current == '/' ? '/$part' : posix.join(current, part));
      try {
        await sftp.mkdir(current);
      } on SftpStatusError {
        // Directory may already exist.
      }
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
    if (sshRunFailed(result)) {
      throw StateError(
        'ln failed (${sshRunFailureLabel(result)}): ${sshRunOutputDetail(result)}',
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
    if (sshRunFailed(result)) {
      throw StateError(
        'mv failed (${sshRunFailureLabel(result)}): ${sshRunOutputDetail(result)}',
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
    if (sshRunFailed(result)) {
      throw StateError(
        'cp failed (${sshRunFailureLabel(result)}): ${sshRunOutputDetail(result)}',
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

  Future<void> copyFile(String source, String destination) async {
    final posix = p.Context(style: p.Style.posix);
    final parent = posix.dirname(destination);
    if (parent.isNotEmpty && parent != '.' && parent != '/') {
      await ensureDirectory(parent);
    }
    final client = await _clientFactory.clientFor(_profile);
    final result = await client.runWithResult(
      'cp -- ${shellSingleQuote(source)} ${shellSingleQuote(destination)}',
      stderr: false,
    );
    if (sshRunFailed(result)) {
      throw StateError(
        'cp failed (${sshRunFailureLabel(result)}): ${sshRunOutputDetail(result)}',
      );
    }
  }

  Future<List<RemoteDirEntry>> listDirectoryEntriesRecursive(String path) async {
    final client = await _clientFactory.clientFor(_profile);
    final result = await client.runWithResult(
      'find ${shellSingleQuote(path)} -mindepth 1 -printf "%P\\t%y\\n"',
      stderr: false,
    );
    if (sshRunFailed(result)) return const [];
    final out = utf8.decode(result.stdout, allowMalformed: true);
    final entries = <RemoteDirEntry>[];
    for (final line in out.split('\n')) {
      if (line.trim().isEmpty) continue;
      final parts = line.split('\t');
      if (parts.length < 2) continue;
      entries.add(RemoteDirEntry(
        name: parts.first,
        isDirectory: parts.last == 'd',
      ));
    }
    return entries;
  }

  /// Best-effort stdout from a remote shell command (empty on failure).
  Future<String> runRemoteCommand(String command) async {
    final result = await execShell(command);
    if (sshRunFailed(result)) return '';
    return utf8.decode(result.stdout, allowMalformed: true);
  }

  /// Runs [command] in the remote login shell and returns the full exit status.
  Future<SSHRunResult> execShell(String command) async {
    final client = await _clientFactory.clientFor(_profile);
    return client.runWithResult(command);
  }

  /// Opens [absolutePath] in the remote OS file manager (best-effort).
  Future<bool> revealInFileManager(
    String absolutePath, {
    required RemoteOs remoteOs,
  }) async {
    final resolved = (await expandHome(absolutePath)).trim();
    if (resolved.isEmpty) return false;

    final client = await _clientFactory.clientFor(_profile);
    final quoted = shellSingleQuote(resolved);
    final cmd = switch (remoteOs) {
      RemoteOs.windows => 'explorer $quoted',
      RemoteOs.posix => 'if command -v xdg-open >/dev/null 2>&1; then '
          'xdg-open -- $quoted; '
          'elif command -v open >/dev/null 2>&1; then '
          'open -- $quoted; '
          'else exit 127; fi',
    };
    final result = await client.runWithResult(cmd, stderr: false);
    return sshRunSucceeded(result);
  }

  Future<String> createTempDir({String? prefix, String? parent}) async {
    final client = await _clientFactory.clientFor(_profile);
    final template = '${prefix ?? 'tmp'}XXXXXX';
    final cmd = parent != null
        ? 'mktemp -d -p ${shellSingleQuote(parent)} $template'
        : 'mktemp -d $template';
    final result = await client.runWithResult(cmd, stderr: false);
    if (sshRunFailed(result)) {
      throw StateError(
        'mktemp failed (${sshRunFailureLabel(result)}): '
        '${sshRunOutputDetail(result)}',
      );
    }
    return utf8.decode(result.stdout, allowMalformed: true).trim();
  }

  Future<void> appendToFile(String path, String content) async {
    final resolved = await expandHome(path);
    await _ensureParentDirs(resolved);
    final encoded = base64.encode(utf8.encode(content));
    final client = await _clientFactory.clientFor(_profile);
    final result = await client.runWithResult(
      'printf \'%s\' ${shellSingleQuote(encoded)} | base64 -d >> ${shellSingleQuote(path)}',
      stderr: false,
    );
    if (sshRunFailed(result)) {
      throw StateError(
        'append failed (${sshRunFailureLabel(result)}): '
        '${sshRunOutputDetail(result)}',
      );
    }
  }

  Future<void> _ensureParentDirs(String resolvedPath) async {
    final parent = p.posix.dirname(resolvedPath);
    if (parent.isEmpty || parent == '.' || parent == '/') return;
    await ensureDirectory(parent);
  }
}
