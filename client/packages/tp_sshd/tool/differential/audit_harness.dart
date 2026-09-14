/// Differential audit harness: a throwaway system sshd plus an in-process
/// tp_sshd server, both on loopback, both authorizing the SAME generated
/// device key — so one audit driver can exercise either server identically.
///
/// The tp_sshd wiring is the proven demo wiring from
/// `example/demo_sshd.dart` (socket adapters, real process/pty factories,
/// the local SFTP filesystem), factored here as library code with the
/// sandbox rooted in the audit temp dir instead of `~/.tp_sshd_demo`.
///
/// VM-only tool code: `dart:io` sockets, processes and `ssh-keygen`.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart' show SSHKeyPair, SSHSocket;
import 'package:dartssh2/protocol.dart'
    show SftpFileAttrs, SftpFileMode, SftpFileOpenMode, SftpName;
import 'package:tp_sshd/tp_sshd.dart';

/// Thrown when the system sshd binary cannot launch on this machine.
///
/// The audit runner converts this into a clean SKIPPED exit so the package
/// suite stays green on machines without OpenSSH.
class SshdUnavailableException implements Exception {
  const SshdUnavailableException(this.reason);

  final String reason;

  @override
  String toString() => 'SshdUnavailableException: $reason';
}

/// The two audit servers, up and accepting connections on loopback.
class AuditServers {
  AuditServers._({
    required this.sshdPort,
    required this.tpdPort,
    required this.deviceKeyPem,
    required this.devicePubLine,
    required this.username,
    required this.tempDir,
    required this.sshdLogPath,
    required ServerSocket listener,
    required StreamController<SSHSocket> connections,
    required SSHServer tpServer,
    required File sshdPidFile,
  }) : _listener = listener,
       _connections = connections,
       _tpServer = tpServer,
       _sshdPidFile = sshdPidFile;

  /// Loopback port of the system sshd, or 0 when it was not launched
  /// (`useSystemSshd: false`).
  final int sshdPort;

  /// Loopback port of the in-process tp_sshd server.
  final int tpdPort;

  /// The PEM private key both servers authorize. The audit driver (and the
  /// smoke test's SSHClient) authenticates with this key.
  final String deviceKeyPem;

  /// The device public key as an `authorized_keys` line.
  final String devicePubLine;

  /// The username both servers expect (the local user; sshd needs a real
  /// account to authorize).
  final String username;

  /// The audit temp dir holding keys, sshd config and the sshd log.
  ///
  /// Kept alive after [close] so sshd DEBUG3 traces can be inspected.
  final Directory tempDir;

  /// Where the system sshd writes its DEBUG3 log (`sshd -E`).
  final String sshdLogPath;

  final ServerSocket _listener;
  final StreamController<SSHSocket> _connections;
  final SSHServer _tpServer;
  final File _sshdPidFile;
  var _closed = false;

  /// Stops both servers. The temp dir (and sshd log) is left in place.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;

    // sshd daemonizes, so the only handle back to it is the PidFile.
    if (_sshdPidFile.existsSync()) {
      final pid = int.tryParse(_sshdPidFile.readAsStringSync().trim());
      if (pid != null) {
        Process.killPid(pid, ProcessSignal.sigterm);
      }
    }
    await _listener.close();
    await _connections.close();
    await _tpServer.close();
  }
}

/// Launches a throwaway system sshd plus an in-process tp_sshd on loopback.
///
/// sshd config: ephemeral port (bind-and-release probe), 127.0.0.1 only,
/// our generated device key authorized, password auth off, StrictModes off
/// (temp dir), Subsystem sftp internal-sftp.
///
/// Throws [SshdUnavailableException] when the system sshd cannot launch —
/// the caller converts that into a skip, never a suite failure.
Future<AuditServers> startAuditServers({bool useSystemSshd = true}) async {
  final dir = await Directory.systemTemp.createTemp('tp_diff_');
  final username = Platform.environment['USER'] ?? 'audituser';

  // The SAME device key authorizes both servers: sshd reads it from
  // authorized_keys, tp_sshd's authenticate callback compares the pub blob.
  await _generateKey(dir, 'host_key', 'tp-diff-sshd-host');
  await _generateKey(dir, 'tp_host_key', 'tp-diff-tp-sshd-host');
  await _generateKey(dir, 'device_key', 'tp-diff-device');
  final deviceKeyPem = File('${dir.path}/device_key').readAsStringSync();
  final devicePubLine =
      File('${dir.path}/device_key.pub').readAsStringSync().trim();
  File('${dir.path}/authorized_keys').writeAsStringSync('$devicePubLine\n');

  final sftpRoot = Directory('${dir.path}/sftp-root')..createSync();

  var sshdPort = 0;
  File? sshdPidFile;
  String sshdLogPath = '';
  if (useSystemSshd) {
    final launched = await _launchSystemSshd(dir);
    sshdPort = launched.port;
    sshdPidFile = launched.pidFile;
    sshdLogPath = launched.logPath;
  }

  // tp_sshd side: the demo wiring over a fresh loopback listener. The port
  // comes from the bound listener itself, so there is no release/bind race.
  final hostKey = SSHKeyPair.fromPem(
    File('${dir.path}/tp_host_key').readAsStringSync(),
  ).single;
  final authorizedKeyBlob = _publicKeyBlob(
    File('${dir.path}/device_key.pub'),
  );

  final listener = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final connections = StreamController<SSHSocket>();
  final tpServer = await SSHServer.bind(
    StreamIterator(connections.stream),
    config: SSHServerConfig(
      hostKeyPair: hostKey,
      expectedUsername: username,
      authenticate: (request) async => _bytesEqual(
        request.publicKey,
        authorizedKeyBlob,
      ),
      processFactory: _spawnProcess,
      shellExecFactory: _spawnShellExec,
      ptyFactory: _spawnPty,
      hostInfo: _hostInfo,
      sftpFileSystem: LocalSftpFileSystem(sftpRoot.path),
      forwarding: SSHForwardingConfig(
        allowTcpForwarding: SshTcpForwardingMode.both,
        dialSocket: (host, port) async {
          final socket = await Socket.connect(host, port);
          return _IoForwardConnection(socket);
        },
        bindServerSocket: (address, port) async {
          final socket = await ServerSocket.bind(address, port);
          return _IoServerSocketHandle(socket);
        },
      ),
    ),
  );

  listener.listen(
    (socket) => connections.add(_AcceptedSocket(socket)),
    onError: connections.addError,
  );

  return AuditServers._(
    sshdPort: sshdPort,
    tpdPort: listener.port,
    deviceKeyPem: deviceKeyPem,
    devicePubLine: devicePubLine,
    username: username,
    tempDir: dir,
    sshdLogPath: sshdLogPath,
    listener: listener,
    connections: connections,
    tpServer: tpServer,
    sshdPidFile: sshdPidFile ?? File('${dir.path}/sshd.pid'),
  );
}

// ---------------------------------------------------------------------------
// System sshd launch
// ---------------------------------------------------------------------------

const _sshdBinary = '/usr/sbin/sshd';

/// The system sshd binary the harness launches.
///
/// Overridable with the `TP_DIFF_SSHD` environment variable so the
/// skip path (missing sshd) can be exercised on machines that have it.
String get _sshdBinaryPath => Platform.environment['TP_DIFF_SSHD'] ?? _sshdBinary;

/// Bind-and-release port probe: returns a currently free loopback port.
///
/// The release/bind window is a race, so [_launchSystemSshd] retries.
Future<int> _probeFreePort() async {
  final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = probe.port;
  await probe.close();
  return port;
}

Future<({int port, File pidFile, String logPath})> _launchSystemSshd(
  Directory dir,
) async {
  const maxAttempts = 3;
  for (var attempt = 1; attempt <= maxAttempts; attempt++) {
    final port = await _probeFreePort();
    final configPath = '${dir.path}/sshd_config';
    final logPath = '${dir.path}/sshd.log';
    File(configPath).writeAsStringSync('''
ListenAddress 127.0.0.1
HostKey ${dir.path}/host_key
AuthorizedKeysFile ${dir.path}/authorized_keys
PubkeyAuthentication yes
PasswordAuthentication no
KbdInteractiveAuthentication no
UsePAM no
StrictModes no
Subsystem sftp internal-sftp
PidFile ${dir.path}/sshd.pid
LogLevel DEBUG3
''');

    ProcessResult result;
    try {
      result = await Process.run(_sshdBinaryPath, [
        '-f',
        configPath,
        '-E',
        logPath,
        '-p',
        '$port',
      ]);
    } on ProcessException catch (error) {
      throw SshdUnavailableException(
        'cannot execute $_sshdBinaryPath: ${error.message}',
      );
    }
    if (result.exitCode == 0) {
      return (
        port: port,
        pidFile: File('${dir.path}/sshd.pid'),
        logPath: logPath,
      );
    }

    // Most likely the probe's port was taken between release and bind;
    // retry with a fresh port. Anything else exhausts the attempts and
    // reports the sshd log below.
  }
  final log = File('${dir.path}/sshd.log');
  final tail = log.existsSync()
      ? log
            .readAsLinesSync()
            .reversed
            .take(10)
            .toList()
            .reversed
            .join('\n')
      : '(no log)';
  throw SshdUnavailableException(
    '$_sshdBinary exited non-zero $maxAttempts times; last log lines:\n$tail',
  );
}

Future<void> _generateKey(
  Directory dir,
  String name,
  String comment,
) async {
  final result = await Process.run('ssh-keygen', [
    '-t',
    'ed25519',
    '-N',
    '',
    '-C',
    comment,
    '-f',
    '${dir.path}/$name',
  ]);
  if (result.exitCode != 0) {
    throw StateError('ssh-keygen failed: ${result.stderr}');
  }
}

/// The OpenSSH wire blob of a public key file (its second field, base64).
Uint8List _publicKeyBlob(File pubFile) {
  final fields = pubFile.readAsStringSync().trim().split(' ');
  if (fields.length < 2) {
    throw StateError('not an OpenSSH public key: ${pubFile.path}');
  }
  return Uint8List.fromList(base64Decode(fields[1]));
}

bool _bytesEqual(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

SSHHostInfo _hostInfo() => SSHHostInfo(
      platform: Platform.operatingSystem,
      osUser: Platform.environment['USER'] ?? 'unknown',
      elevated: false,
      inDocker: File('/.dockerenv').existsSync(),
      shell: Platform.environment['SHELL'] ?? '/bin/sh',
    );

// ---------------------------------------------------------------------------
// Exec / pty seams (the demo wiring, quieted for audit runs)
// ---------------------------------------------------------------------------

Future<SSHServerProcess?> _spawnProcess(
  List<String> argv,
  String? cwd,
  Map<String, String> env,
) async {
  try {
    final process = await Process.start(
      argv.first,
      argv.skip(1).toList(),
      workingDirectory: cwd,
      environment: {...Platform.environment, ...env},
    );
    return _IoServerProcess(process);
  } on Object {
    return null;
  }
}

/// Serves a plain command-string `exec` the way OpenSSH serves
/// `ssh host "command"`: through the host's native shell.
Future<SSHServerProcess?> _spawnShellExec(
  String command,
  Map<String, String> env,
) async {
  return _spawnProcess(
    ['/bin/sh', '-c', command],
    null,
    env,
  );
}

Future<SSHServerPty?> _spawnPty(SSHPtyDimensions initial) async {
  final shell = Platform.environment['SHELL'] ?? '/bin/bash';
  try {
    // Pure dart:io cannot allocate a pty; util-linux `script` owns one and
    // pipes the session through stdio (no window-change ioctl).
    final process = await Process.start(
      'script',
      ['-qefc', shell, '/dev/null'],
      environment: {
        ...Platform.environment,
        ...initial.environment,
        'TERM': initial.environment['TERM'] ?? 'xterm-256color',
      },
    );
    return _IoServerPty(process);
  } on Object {
    return null;
  }
}

class _IoServerProcess implements SSHServerProcess {
  _IoServerProcess(this._process);

  final Process _process;

  @override
  Stream<Uint8List> get stdout => _process.stdout.cast<Uint8List>();

  @override
  Stream<Uint8List> get stderr => _process.stderr.cast<Uint8List>();

  @override
  StreamSink<List<int>> get stdin => _process.stdin;

  @override
  Future<int> get exitCode => _process.exitCode;

  @override
  void kill() => _process.kill();
}

class _IoServerPty extends _IoServerProcess implements SSHServerPty {
  _IoServerPty(super.process);

  static const _signals = {
    'INT': ProcessSignal.sigint,
    'TERM': ProcessSignal.sigterm,
    'HUP': ProcessSignal.sighup,
    'KILL': ProcessSignal.sigkill,
  };

  @override
  void resize(int columns, int rows) {
    // `script` owns the pty from a separate process; resizing would need an
    // ioctl this harness does not wire up.
  }

  @override
  void signal(String name) {
    final signal = _signals[name];
    if (signal == null) return;
    _process.kill(signal);
  }
}

// ---------------------------------------------------------------------------
// Socket / forwarding adapters: dart:io types onto the tp_sshd seams
// ---------------------------------------------------------------------------

/// An accepted [Socket] exposed as the [SSHSocket] the server consumes.
class _AcceptedSocket implements SSHSocket {
  _AcceptedSocket(this._socket);

  final Socket _socket;

  @override
  Stream<Uint8List> get stream => _socket;

  @override
  StreamSink<List<int>> get sink => _socket;

  @override
  Future<void> get done => _socket.done;

  @override
  Future<void> close() => _socket.close();

  @override
  void destroy() => _socket.destroy();

  @override
  Future<void> flush() => _socket.flush();
}

/// A real [ServerSocket] behind one `tcpip-forward` request.
class _IoServerSocketHandle implements ServerSocketHandle {
  _IoServerSocketHandle(this._socket);

  final ServerSocket _socket;

  @override
  int get port => _socket.port;

  @override
  Stream<ForwardConnection> get connections =>
      _socket.map(_IoForwardConnection.new);

  @override
  Future<void> close() => _socket.close();
}

/// One accepted forwarded TCP connection.
class _IoForwardConnection implements ForwardConnection {
  _IoForwardConnection(this._socket);

  final Socket _socket;

  @override
  Stream<Uint8List> get input => _socket;

  @override
  StreamSink<List<int>> get output => _socket;

  @override
  Future<void> get done => _socket.done;

  @override
  InternetAddress get remoteAddress => _socket.remoteAddress;

  @override
  int get remotePort => _socket.remotePort;

  @override
  void destroy() => _socket.destroy();
}

// ---------------------------------------------------------------------------
// SFTP over the local filesystem, jailed to the sandbox root
// ---------------------------------------------------------------------------

/// [SftpFileSystem] over dart:io, mapping `/` onto [root]. The jail is
/// string-normalized (`.`/`..` resolved before the root is prepended).
/// Requests on one handle are serialized with a lock chain — the package
/// dispatches SFTP requests concurrently and dart:io position+read/write
/// pairs are not atomic.
///
/// Ported verbatim from `example/demo_sshd.dart`; only the root differs
/// (the audit temp dir's sandbox instead of the demo directory).
class LocalSftpFileSystem implements SftpFileSystem {
  LocalSftpFileSystem(this.root);

  final String root;

  @override
  Future<SftpFileAttrs> stat(String path) async {
    final fsPath = _resolve(path);
    final stat = FileStat.statSync(fsPath);
    if (stat.type == FileSystemEntityType.notFound) {
      throw SftpNoSuchFileException(path);
    }
    return _attrsOf(stat);
  }

  @override
  Future<SftpDirListing> openDir(String path) async {
    final fsPath = _resolve(path);
    final type = FileSystemEntity.typeSync(fsPath);
    if (type == FileSystemEntityType.notFound) {
      throw SftpNoSuchFileException(path);
    }
    if (type != FileSystemEntityType.directory) {
      throw SftpFileSystemException('not a directory: $path');
    }
    return _IoDirListing(Directory(fsPath));
  }

  @override
  Future<SftpHandle> openFile(
    String path,
    SftpFileOpenMode mode,
    SftpFileAttrs? attrs,
  ) async {
    final fsPath = _resolve(path);
    final type = FileSystemEntity.typeSync(fsPath);
    if (type == FileSystemEntityType.directory) {
      throw SftpFileSystemException('is a directory: $path');
    }
    if (type != FileSystemEntityType.notFound) {
      if (mode.flag & SftpFileOpenMode.exclusive.flag != 0) {
        throw SftpFileExistsException(path);
      }
    } else {
      if (mode.flag & SftpFileOpenMode.create.flag == 0) {
        throw SftpNoSuchFileException(path);
      }
      final parent = File(fsPath).parent;
      if (!parent.existsSync()) {
        throw SftpNoSuchFileException(path);
      }
    }
    final wantWrite = mode.flag & SftpFileOpenMode.write.flag != 0;
    final file = File(fsPath).openSync(
      mode: wantWrite ? FileMode.write : FileMode.read,
    );
    if (mode.flag & SftpFileOpenMode.truncate.flag != 0) {
      file.truncateSync(0);
    }
    return _IoSftpHandle(
      file,
      append: mode.flag & SftpFileOpenMode.append.flag != 0,
    );
  }

  @override
  Future<void> mkdir(String path, SftpFileAttrs attrs) async {
    final fsPath = _resolve(path);
    if (FileSystemEntity.typeSync(fsPath) != FileSystemEntityType.notFound) {
      throw SftpFileExistsException(path);
    }
    try {
      Directory(fsPath).createSync();
    } on FileSystemException catch (error) {
      _throwMapped(error, path);
    }
  }

  @override
  Future<void> rmdir(String path) async {
    final fsPath = _resolve(path);
    if (fsPath == root) {
      throw SftpFileSystemException('cannot remove the root');
    }
    if (FileSystemEntity.typeSync(fsPath) == FileSystemEntityType.notFound) {
      throw SftpNoSuchFileException(path);
    }
    try {
      Directory(fsPath).deleteSync();
    } on FileSystemException catch (error) {
      _throwMapped(error, path);
    }
  }

  @override
  Future<void> unlink(String path) async {
    final fsPath = _resolve(path);
    final type = FileSystemEntity.typeSync(fsPath);
    if (type == FileSystemEntityType.notFound) {
      throw SftpNoSuchFileException(path);
    }
    if (type == FileSystemEntityType.directory) {
      throw SftpFileSystemException('is a directory: $path');
    }
    try {
      File(fsPath).deleteSync();
    } on FileSystemException catch (error) {
      _throwMapped(error, path);
    }
  }

  @override
  Future<void> rename(String from, String to) async {
    final fsFrom = _resolve(from);
    final fsTo = _resolve(to);
    if (FileSystemEntity.typeSync(fsFrom) == FileSystemEntityType.notFound) {
      throw SftpNoSuchFileException(from);
    }
    if (FileSystemEntity.typeSync(fsTo) != FileSystemEntityType.notFound) {
      throw SftpFileExistsException(to);
    }
    try {
      if (FileSystemEntity.typeSync(fsFrom) == FileSystemEntityType.directory) {
        Directory(fsFrom).renameSync(fsTo);
      } else {
        File(fsFrom).renameSync(fsTo);
      }
    } on FileSystemException catch (error) {
      _throwMapped(error, from);
    }
  }

  @override
  Future<String> realpath(String path) async => _normalize(path);

  /// The on-disk path for an SFTP path: normalized, then joined under [root].
  String _resolve(String path) => _joinRoot(_normalize(path));

  String _normalize(String path) {
    final segments = <String>[];
    for (final segment in path.split('/')) {
      if (segment.isEmpty || segment == '.') continue;
      if (segment == '..') {
        if (segments.isNotEmpty) segments.removeLast();
        continue;
      }
      segments.add(segment);
    }
    return '/${segments.join('/')}';
  }

  String _joinRoot(String normalized) =>
      normalized == '/' ? root : '$root$normalized';

  static SftpFileAttrs _attrsOf(FileStat stat) => SftpFileAttrs(
        size: stat.size,
        mode: SftpFileMode.value(stat.mode),
        accessTime: stat.accessed.millisecondsSinceEpoch ~/ 1000,
        modifyTime: stat.modified.millisecondsSinceEpoch ~/ 1000,
      );

  static Never _throwMapped(FileSystemException error, String path) {
    switch (error.osError?.errorCode) {
      case 2: // ENOENT
      case 20: // ENOTDIR
        throw SftpNoSuchFileException(path);
      case 13: // EACCES
        throw SftpPermissionDeniedException(path);
      case 17: // EEXIST
        throw SftpFileExistsException(path);
      case 39: // ENOTEMPTY
        throw SftpFileSystemException('directory not empty: $path');
      default:
        throw SftpFileSystemException(error.message);
    }
  }
}

class _IoSftpHandle implements SftpHandle {
  _IoSftpHandle(this._file, {required this.append});

  final RandomAccessFile _file;
  final bool append;

  /// Serialized operations: the SFTP server dispatches concurrently, but a
  /// position+read/write pair on one handle must stay atomic.
  Future<void> _lock = Future.value();

  @override
  Future<Uint8List> read(int offset, int length) {
    return _enqueue(() async {
      await _file.setPosition(offset);
      return _file.read(length);
    });
  }

  @override
  Future<void> write(int offset, Uint8List data) {
    return _enqueue(() async {
      final target = append ? await _file.length() : offset;
      await _file.setPosition(target);
      await _file.writeFrom(data);
    });
  }

  @override
  Future<void> close() => _enqueue(_file.close);

  Future<T> _enqueue<T>(Future<T> Function() operation) {
    final result = _lock.then((_) => operation());
    _lock = result.then((_) {}, onError: (_) {});
    return result;
  }
}

class _IoDirListing implements SftpDirListing {
  _IoDirListing(this._directory);

  final Directory _directory;
  bool _closed = false;

  @override
  Future<List<SftpName>> read() async {
    if (_closed) return const [];
    _closed = true;
    final names = <SftpName>[];
    await for (final entity in _directory.list()) {
      final stat = entity.statSync();
      names.add(
        SftpName(
          filename: _baseName(entity.path),
          longname: _longName(stat, _baseName(entity.path)),
          attr: LocalSftpFileSystem._attrsOf(stat),
        ),
      );
    }
    return names;
  }

  @override
  Future<void> close() async {
    _closed = true;
  }
}

String _baseName(String path) {
  final index = path.lastIndexOf('/');
  return index < 0 ? path : path.substring(index + 1);
}

/// A lazy `ls -l`-style long name; clients only display it.
String _longName(FileStat stat, String name) {
  final mode = stat.modeString();
  final kind = stat.type == FileSystemEntityType.directory ? 'd' : '-';
  final size = stat.size.toString().padLeft(8);
  final mtime =
      stat.modified.toIso8601String().substring(0, 16).replaceAll('T', ' ');
  final owner = Platform.environment['USER'] ?? 'user';
  return '$kind$mode 1 $owner $size $mtime $name';
}
