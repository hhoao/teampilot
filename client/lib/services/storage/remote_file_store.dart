import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:dartssh2/dartssh2.dart' show SSHRunResult;
import 'package:path/path.dart' as p;

import '../io/filesystem.dart';
import '../host/host_one_shot_runner.dart';
import '../host/process_run_handle.dart';
import '../ssh/ssh_client_factory.dart';
import '../ssh/ssh_storage_io.dart';
import '../ssh/ssh_transport_close.dart';
import '../ssh/ssh_run_result.dart';
import '../ssh/worker/ssh_worker_storage_client.dart';
import '../ssh/worker/ssh_worker_storage_types.dart';
import '../../models/runtime_target.dart';
import '../../models/ssh_profile.dart';
import 'remote_home_resolver.dart';

class RemoteDirEntry {
  const RemoteDirEntry({required this.name, required this.isDirectory});

  final String name;
  final bool isDirectory;
}

Future<SshWorkerStorageFacade> Function({Duration timeout})
_defaultRemoteStorageFor(SshClientFactory factory, SshProfile profile) =>
    ({Duration timeout = SshStorageIo.ioTimeout}) =>
        factory.storageFor(profile, timeout: timeout);

class RemoteFileStore {
  RemoteFileStore({
    required SshProfile profile,
    required SshClientFactory clientFactory,
    Future<SshWorkerStorageFacade> Function({Duration timeout})? storageFor,
  }) : _profile = profile,
       _clientFactory = clientFactory,
       _storageFor =
           storageFor ?? _defaultRemoteStorageFor(clientFactory, profile);

  final SshProfile _profile;
  final SshClientFactory _clientFactory;
  final Future<SshWorkerStorageFacade> Function({Duration timeout}) _storageFor;
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

  Future<SshWorkerStorageFacade> _ensureConnected({
    Duration timeout = SshStorageIo.ioTimeout,
  }) => _storageFor(timeout: timeout);

  Future<T> _tracked<T>(
    Future<T> Function(Duration timeout) operation, {
    Duration timeout = SshStorageIo.ioTimeout,
    bool retryOnTransportClosure = true,
  }) => _clientFactory.runTracked(_profile.id, () async {
    try {
      return await operation(timeout);
    } on Object catch (error) {
      if (!retryOnTransportClosure || !_isRetryableTransportClosure(error)) {
        rethrow;
      }
      _clientFactory.disconnectStorage(
        _profile.id,
        reason: SshTransportCloseReason.transportError,
      );
      // Retrying once is safe for the idempotent file operations in this
      // class; arbitrary shell commands stay outside this boundary.
      return operation(timeout);
    }
  });

  bool _isRetryableTransportClosure(Object error) {
    if (error is SshWorkerTransportException) {
      return const {
        'transport_closed',
        'transport_error',
        'transport_timeout',
        'storage_not_connected',
      }.contains(error.code);
    }
    final message = error.toString().toLowerCase();
    return message.contains('sftp channel closed') ||
        message.contains('sftp client closed') ||
        message.contains('ssh client closed') ||
        message.contains('ssh transport closed') ||
        message.contains('transport is closed');
  }

  static bool _isMissing(SshWorkerTransportException error) =>
      error.code == 'sftp_no_such_file';

  static bool _isSftpFailure(SshWorkerTransportException error) =>
      _isMissing(error) || error.code == 'sftp_error';

  static FsEntityKind _entityKind(String kind) => switch (kind) {
    'directory' => FsEntityKind.directory,
    'symlink' => FsEntityKind.symlink,
    _ => FsEntityKind.file,
  };

  Future<String> expandHome(String path) async {
    if (!path.startsWith('~')) return path;
    final home = await _remoteHome();
    if (path == '~' || path == '~/') return home;
    final rest = path.startsWith('~/') ? path.substring(2) : path.substring(1);
    if (rest.isEmpty) return home;
    return p.posix.join(home, rest);
  }

  Future<FsEntityKind> statKind(String path) async {
    return (await stat(path)).kind;
  }

  /// Full [FsStat] including size/mtime from SFTP attrs when available.
  Future<FsStat> stat(String path) => _tracked((timeout) async {
    try {
      final storage = await _ensureConnected(timeout: timeout);
      final resolved = await expandHome(path);
      final attrs = await storage.stat(resolved, timeout: timeout);
      return FsStat(
        kind: _entityKind(attrs.kind),
        size: attrs.size,
        mtime: attrs.modifyTime != null
            ? DateTime.fromMillisecondsSinceEpoch(attrs.modifyTime! * 1000)
            : null,
      );
    } on SshWorkerTransportException catch (error) {
      if (_isMissing(error)) {
        return const FsStat(kind: FsEntityKind.notFound);
      }
      rethrow;
    }
  });

  /// Reads the immediate target of a symlink, or null if not a link / missing.
  Future<String?> readlink(String path) => _tracked((timeout) async {
    try {
      final storage = await _ensureConnected(timeout: timeout);
      final resolved = await expandHome(path);
      return await storage.readlink(resolved, timeout: timeout);
    } on SshWorkerTransportException catch (error) {
      if (!_isSftpFailure(error)) rethrow;
      return null;
    }
  });

  /// Fully resolves [path] to its canonical absolute path, or null on failure.
  Future<String?> realpath(String path) => _tracked((timeout) async {
    try {
      final storage = await _ensureConnected(timeout: timeout);
      final resolved = await expandHome(path);
      return await storage.realpath(resolved, timeout: timeout);
    } on SshWorkerTransportException catch (error) {
      if (!_isSftpFailure(error)) rethrow;
      return null;
    }
  });

  Future<bool> fileExists(String path) => _tracked((timeout) async {
    try {
      final storage = await _ensureConnected(timeout: timeout);
      final resolved = await expandHome(path);
      await storage.stat(resolved, timeout: timeout);
      return true;
    } on SshWorkerTransportException catch (error) {
      if (_isMissing(error)) return false;
      rethrow;
    }
  });

  Future<String?> readFile(String path) => _tracked((timeout) async {
    try {
      final storage = await _ensureConnected(timeout: timeout);
      final resolved = await expandHome(path);
      final bytes = await storage.readBytes(resolved, timeout: timeout);
      return utf8.decode(bytes);
    } on SshWorkerTransportException catch (error) {
      if (_isMissing(error)) return null;
      rethrow;
    }
  });

  Future<List<int>?> readFileBytes(String path) => _tracked((timeout) async {
    try {
      final storage = await _ensureConnected(timeout: timeout);
      final resolved = await expandHome(path);
      return await storage.readBytes(resolved, timeout: timeout);
    } on SshWorkerTransportException catch (error) {
      if (_isMissing(error)) return null;
      rethrow;
    }
  });

  Future<List<int>?> readFileBytesRange(
    String path, {
    required int offset,
    required int length,
  }) => _tracked((timeout) async {
    try {
      final storage = await _ensureConnected(timeout: timeout);
      final resolved = await expandHome(path);
      return await storage.readBytes(
        resolved,
        offset: offset,
        length: length,
        timeout: timeout,
      );
    } on SshWorkerTransportException catch (error) {
      if (_isMissing(error)) return null;
      rethrow;
    }
  });

  Future<void> writeFile(String path, String contents) =>
      _tracked((timeout) async {
        final storage = await _ensureConnected(timeout: timeout);
        final resolved = await expandHome(path);
        await _ensureParentDirs(resolved);
        final bytes = Uint8List.fromList(utf8.encode(contents));
        await storage.writeBytes(resolved, bytes, timeout: timeout);
      });

  Future<List<String>> listDirectory(String path) async {
    final entries = await listDirectoryEntries(path);
    return entries.map((e) => e.name).toList();
  }

  Future<List<RemoteDirEntry>> listDirectoryEntries(String path) => _tracked((
    timeout,
  ) async {
    final storage = await _ensureConnected(timeout: timeout);
    final resolved = await expandHome(path);
    final names = await storage.listDirectory(resolved, timeout: timeout);
    return [
      for (final n in names)
        if (n.name != '.' && n.name != '..')
          RemoteDirEntry(name: n.name, isDirectory: n.stat.kind == 'directory'),
    ];
  });

  Future<void> writeBytes(String path, Uint8List bytes) =>
      _tracked((timeout) async {
        final storage = await _ensureConnected(timeout: timeout);
        final resolved = await expandHome(path);
        await _ensureParentDirs(resolved);
        await storage.writeBytes(resolved, bytes, timeout: timeout);
      });

  Future<void> appendBytes(String path, Uint8List bytes) => _tracked((
    timeout,
  ) async {
    final storage = await _ensureConnected(timeout: timeout);
    final resolved = await expandHome(path);
    await _ensureParentDirs(resolved);
    await storage.writeBytes(resolved, bytes, append: true, timeout: timeout);
  }, retryOnTransportClosure: false);

  Future<void> ensureDirectory(String path) async {
    final resolved = await expandHome(path);
    if (resolved.isEmpty || resolved == '.' || resolved == '/') return;
    if ((await statKind(resolved)) == FsEntityKind.directory) return;

    final result = await _clientFactory.runOnStorage(
      _profile,
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

  Future<void> _ensureDirectorySftp(String absolutePosixPath) =>
      _tracked((timeout) async {
        final storage = await _ensureConnected(timeout: timeout);
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
            await storage.mkdir(current, timeout: timeout);
          } on SshWorkerTransportException catch (error) {
            if (!_isSftpFailure(error)) rethrow;
            // Directory may already exist.
          }
        }
      });

  Future<void> removeRecursive(String absolutePosixPath) async {
    await _clientFactory.runOnStorage(
      _profile,
      'rm -rf -- ${shellSingleQuote(absolutePosixPath)}',
      stderr: false,
    );
  }

  Future<void> createSymlink({
    required String target,
    required String linkPath,
  }) async {
    final parent = p.Context(style: p.Style.posix).dirname(linkPath);
    if (parent.isNotEmpty && parent != '.') {
      await ensureDirectory(parent);
    }
    await removeRecursive(linkPath);
    final result = await _clientFactory.runOnStorage(
      _profile,
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
    final result = await _clientFactory.runOnStorage(
      _profile,
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
    final result = await _clientFactory.runOnStorage(
      _profile,
      'cp -R -- ${shellSingleQuote('$source/.')} ${shellSingleQuote(destination)}',
      stderr: false,
    );
    if (sshRunFailed(result)) {
      throw StateError(
        'cp failed (${sshRunFailureLabel(result)}): ${sshRunOutputDetail(result)}',
      );
    }
  }

  Future<void> createDirectory(String path) => _tracked((timeout) async {
    final storage = await _ensureConnected(timeout: timeout);
    final resolved = await expandHome(path);
    try {
      await storage.mkdir(resolved, timeout: timeout);
    } on SshWorkerTransportException catch (error) {
      if (!_isSftpFailure(error)) rethrow;
      // Directory might already exist; ignore errors
    }
  });

  Future<void> deleteFile(String path) => _tracked((timeout) async {
    final storage = await _ensureConnected(timeout: timeout);
    final resolved = await expandHome(path);
    try {
      await storage.remove(resolved, timeout: timeout);
    } on SshWorkerTransportException catch (error) {
      if (_isMissing(error)) return;
      rethrow;
    }
  });

  Future<void> disconnect() async {
    _clientFactory.disconnectProfile(
      _profile.id,
      reason: SshTransportCloseReason.remoteFileStoreDisconnect,
    );
  }

  Future<void> copyFile(String source, String destination) async {
    final posix = p.Context(style: p.Style.posix);
    final parent = posix.dirname(destination);
    if (parent.isNotEmpty && parent != '.' && parent != '/') {
      await ensureDirectory(parent);
    }
    final result = await _clientFactory.runOnStorage(
      _profile,
      'cp -- ${shellSingleQuote(source)} ${shellSingleQuote(destination)}',
      stderr: false,
    );
    if (sshRunFailed(result)) {
      throw StateError(
        'cp failed (${sshRunFailureLabel(result)}): ${sshRunOutputDetail(result)}',
      );
    }
  }

  Future<List<RemoteDirEntry>> listDirectoryEntriesRecursive(
    String path,
  ) async {
    final result = await _clientFactory.runOnStorage(
      _profile,
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
      entries.add(
        RemoteDirEntry(name: parts.first, isDirectory: parts.last == 'd'),
      );
    }
    return entries;
  }

  /// Best-effort stdout from a remote shell command (empty on failure).
  Future<String> runRemoteCommand(String command) async {
    final result = await execShell(command);
    if (sshRunFailed(result)) return '';
    return utf8.decode(result.stdout, allowMalformed: true);
  }

  /// Runs [request] on the remote host via login-shell exec (argv-safe quoting).
  Future<HostRunResult> runHost(HostRunRequest request) async {
    return RemoteHostOneShotRunner(execShell: execShell).run(request);
  }

  /// Runs [command] in the remote login shell and returns the full exit status.
  Future<SSHRunResult> execShell(String command) async {
    return _clientFactory.runOnStorage(_profile, command);
  }

  /// Runs [command] on the host with [stdin] bytes; returns the raw result.
  Future<SSHRunResult> execShellWithStdin(
    String command,
    List<int> stdin, {
    Duration timeout = SshStorageIo.provisionPhaseTimeout,
  }) {
    return _clientFactory.runOnStorageWithStdin(
      _profile,
      command,
      stdin: stdin,
      timeout: timeout,
    );
  }

  /// Opens a streaming SSH exec session (no short I/O timeout — caller waits on
  /// [ProcessRunHandle.exitCode]).
  Future<ProcessRunHandle> startShell(String command) =>
      _clientFactory.startProcess(_profile, command);

  /// Opens [absolutePath] in the remote OS file manager (best-effort).
  Future<bool> revealInFileManager(
    String absolutePath, {
    required RemoteOs remoteOs,
  }) async {
    final resolved = (await expandHome(absolutePath)).trim();
    if (resolved.isEmpty) return false;

    final quoted = shellSingleQuote(resolved);
    final cmd = switch (remoteOs) {
      RemoteOs.windows => 'explorer $quoted',
      RemoteOs.posix =>
        'if command -v xdg-open >/dev/null 2>&1; then '
            'xdg-open -- $quoted; '
            'elif command -v open >/dev/null 2>&1; then '
            'open -- $quoted; '
            'else exit 127; fi',
    };
    final result = await _clientFactory.runOnStorage(
      _profile,
      cmd,
      stderr: false,
    );
    return sshRunSucceeded(result);
  }

  Future<String> createTempDir({String? prefix, String? parent}) async {
    final template = '${prefix ?? 'tmp'}XXXXXX';
    final cmd = parent != null
        ? 'mktemp -d -p ${shellSingleQuote(parent)} $template'
        : 'mktemp -d $template';
    final result = await _clientFactory.runOnStorage(
      _profile,
      cmd,
      stderr: false,
    );
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
    final result = await _clientFactory.runOnStorage(
      _profile,
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
