// Demo SSH server wiring every tp_sshd seam to real system resources, so the
// package can be exercised end-to-end with a stock OpenSSH client:
//
//   dart run example/demo_sshd.dart
//
// First run bootstraps throwaway keys with `ssh-keygen` and prints the exact
// ssh/sftp command lines to connect. The SFTP subsystem is jailed to a small
// sandbox directory; exec and interactive shells run as the local user, like
// the app's embedded server eventually will.
//
// VM-only: dart:io sockets, processes and signals.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart' show SSHKeyPair, SSHSocket;
import 'package:dartssh2/protocol.dart'
    show SftpFileAttrs, SftpFileMode, SftpFileOpenMode, SftpName;
import 'package:tp_sshd/tp_sshd.dart';

Future<void> main(List<String> args) async {
  final options = _DemoOptions.parse(args);
  await _bootstrapKeys(options);
  await _bootstrapSandbox(options);

  final hostKey = SSHKeyPair.fromPem(
    File('${options.keysDir}/host_key').readAsStringSync(),
  ).single;
  final authorizedKeyBlob = _publicKeyBlob('${options.keysDir}/device_key.pub');

  final listener = await ServerSocket.bind(
    InternetAddress.loopbackIPv4,
    options.port,
  );
  final connections = StreamController<SSHSocket>();
  final server = await SSHServer.bind(
    StreamIterator(connections.stream),
    config: SSHServerConfig(
      hostKeyPair: hostKey,
      expectedUsername: options.username,
      authenticate: (request) async => _bytesEqual(
        request.publicKey,
        authorizedKeyBlob,
      ),
      processFactory: (argv, cwd, env) => _spawnProcess(argv, cwd, env),
      ptyFactory: _spawnPty,
      hostInfo: _hostInfo,
      sftpFileSystem: LocalSftpFileSystem(options.root),
      bindServerSocket: (address, port) async {
        final socket = await ServerSocket.bind(address, port);
        return _IoServerSocketHandle(socket);
      },
      // Keep the log readable: the transport traces every packet loop.
      printDebug: (message) {
        if (message == null || message.contains('_processPackets')) return;
        print('[debug] $message');
      },
    ),
  );

  listener.listen(
    (socket) {
      print('-- accepted ${socket.remoteAddress.address}:${socket.remotePort}');
      connections.add(_AcceptedSocket(socket));
    },
    onError: (Object error) => print('!! listener error: $error'),
    onDone: () => print('-- listener closed'),
  );

  _printInstructions(options);

  ProcessSignal.sigint.watch().first.then((_) async {
    print('\n-- shutting down');
    await listener.close();
    await connections.close();
    await server.close();
    exit(0);
  });

  await server.done;
}

// ---------------------------------------------------------------------------
// Options, key bootstrap, startup output
// ---------------------------------------------------------------------------

class _DemoOptions {
  _DemoOptions({
    required this.port,
    required this.username,
    required this.keysDir,
    required this.root,
  });

  final int port;
  final String username;
  final String keysDir;
  final String root;

  static _DemoOptions parse(List<String> args) {
    var port = 2222;
    var username = Platform.environment['USER'] ?? 'demo';
    var keysDir = Platform.environment['HOME'] != null
        ? '${Platform.environment['HOME']}/.tp_sshd_demo'
        : '.tp_sshd_demo';
    var root = '$keysDir/sftp-root';

    for (var i = 0; i < args.length; i++) {
      switch (args[i]) {
        case '--port':
          port = int.parse(args[++i]);
        case '--user':
          username = args[++i];
        case '--keys':
          keysDir = args[++i];
        case '--root':
          root = args[++i];
        default:
          throw ArgumentError('unknown option: ${args[i]}');
      }
    }
    return _DemoOptions(
      port: port,
      username: username,
      keysDir: keysDir,
      root: root,
    );
  }
}

/// Generates the throwaway host key and client device key on first run, and
/// writes a known_hosts entry covering the demo address.
Future<void> _bootstrapKeys(_DemoOptions options) async {
  Directory(options.keysDir).createSync(recursive: true);
  await _ensureKey('${options.keysDir}/host_key', 'tp-sshd-demo-host');
  await _ensureKey('${options.keysDir}/device_key', 'tp-sshd-demo-device');
  File('${options.keysDir}/known_hosts').writeAsStringSync(
    '[127.0.0.1]:${options.port} ssh-ed25519 '
    '${base64.encode(_publicKeyBlob('${options.keysDir}/host_key.pub'))}\n',
  );
}

Future<void> _ensureKey(String path, String comment) async {
  if (File(path).existsSync()) return;
  final result = await Process.run('ssh-keygen', [
    '-t',
    'ed25519',
    '-N',
    '',
    '-C',
    comment,
    '-f',
    path,
  ]);
  if (result.exitCode != 0) {
    throw StateError('ssh-keygen failed: ${result.stderr}');
  }
}

/// The OpenSSH wire blob of a public key file (its second field, base64).
Uint8List _publicKeyBlob(String pubPath) {
  final fields = File(pubPath).readAsStringSync().trim().split(' ');
  if (fields.length < 2) {
    throw StateError('not an OpenSSH public key: $pubPath');
  }
  return base64.decode(fields[1]);
}

bool _bytesEqual(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Seeds the SFTP sandbox so the very first `sftp` session has content.
Future<void> _bootstrapSandbox(_DemoOptions options) async {
  final root = Directory(options.root)..createSync(recursive: true);
  final hello = File('${root.path}/hello.txt');
  if (!hello.existsSync()) {
    await hello.writeAsString('Hello from the tp_sshd demo SFTP sandbox.\n');
  }
  final docs = Directory('${root.path}/docs')..createSync(recursive: true);
  final readme = File('${docs.path}/readme.md');
  if (!readme.existsSync()) {
    await readme.writeAsString(
      '# tp_sshd demo\n\nEverything under `/` in an SFTP session maps to '
      '`${root.path}` on this machine.\n',
    );
  }
}

void _printInstructions(_DemoOptions options) {
  final keys = options.keysDir;
  final user = options.username;
  final port = options.port;
  final common = '-p $port -i $keys/device_key '
      '-o UserKnownHostsFile=$keys/known_hosts -o IdentitiesOnly=yes';
  print('''
tp_sshd demo server listening on 127.0.0.1:$port
  username : $user
  sftp root: ${options.root}

Try it with a real OpenSSH client:

  # handshake + publickey auth + structured exec (tp1: grammar, no shell)
  ssh $common $user@127.0.0.1 'tp1:{"argv":["echo","hello","structured","exec"]}'
  ssh $common $user@127.0.0.1 'tp1:{"query":"host-info"}'

  # plain shell strings are refused by design
  ssh $common $user@127.0.0.1 'echo nope'

  # interactive shell through a pty (util-linux `script` backs it)
  ssh -t $common $user@127.0.0.1

  # SFTP: ls/get/put/mkdir, rooted at the sandbox above
  sftp $common $user@127.0.0.1

  # remote port forwarding: serve a local port back over the SSH connection
  python3 -m http.server 18080 &
  ssh $common -R 19080:127.0.0.1:18080 $user@127.0.0.1
  curl http://127.0.0.1:19080/
''');
}

SSHHostInfo _hostInfo() => SSHHostInfo(
      platform: Platform.operatingSystem,
      osUser: Platform.environment['USER'] ?? 'unknown',
      elevated: false,
      inDocker: File('/.dockerenv').existsSync(),
      shell: Platform.environment['SHELL'] ?? '/bin/sh',
    );

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
// Exec / pty seams
// ---------------------------------------------------------------------------

Future<SSHServerProcess?> _spawnProcess(
  List<String> argv,
  String? cwd,
  Map<String, String> env,
) async {
  print('-- exec ${jsonEncode(argv)} (cwd: ${cwd ?? 'inherit'})');
  try {
    final process = await Process.start(
      argv.first,
      argv.skip(1).toList(),
      workingDirectory: cwd,
      environment: {...Platform.environment, ...env},
    );
    return _IoServerProcess(process);
  } on Object catch (error) {
    print('!! exec refused, spawn failed: $error');
    return null;
  }
}

Future<SSHServerPty?> _spawnPty(SSHPtyDimensions initial) async {
  final shell = Platform.environment['SHELL'] ?? '/bin/bash';
  print(
    '-- shell $shell (${initial.columns}x${initial.rows}, '
    'TERM=${initial.environment['TERM'] ?? 'unset'})',
  );
  try {
    // Pure dart:io cannot allocate a pty; util-linux `script` owns one and
    // pipes the session through stdio. Demo-grade: no window-change ioctl.
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
  } on Object catch (error) {
    print('!! shell refused, spawn failed: $error');
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
    // ioctl (or `stty` in-session) this demo does not wire up.
    print('-- window-change ${columns}x$rows (demo: not applied)');
  }

  @override
  void signal(String name) {
    final signal = _signals[name];
    if (signal == null) {
      print('-- signal $name (demo: unknown, dropped)');
      return;
    }
    _process.kill(signal);
  }
}

// ---------------------------------------------------------------------------
// SFTP over the local filesystem, jailed to the sandbox root
// ---------------------------------------------------------------------------

/// [SftpFileSystem] over dart:io, mapping `/` onto [root]. The jail is
/// string-normalized (`.`/`..` resolved before the root is prepended), good
/// enough for a demo sandbox without symlink chasing. Requests on one handle
/// are serialized with a lock chain — the package dispatches SFTP requests
/// concurrently and dart:io position+read/write pairs are not atomic.
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
  Future<String> realpath(String path) async {
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

  /// The on-disk path for an SFTP path: normalized, then joined under [root].
  String _resolve(String path) => _joinRoot(_normalizeSync(path));

  String _normalizeSync(String path) {
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
