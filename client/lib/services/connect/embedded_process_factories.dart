/// Exec/pty factories for the embedded SSH server.
///
/// `shell` requests get the OS-native shell in a flutter_pty pseudo-terminal
/// (`powershell.exe` on Windows, `$SHELL` / `/bin/bash` elsewhere); structured
/// `exec` requests spawn their argv directly with `Process.start` — never
/// through a shell. Both prepend TeamPilot's managed Node toolchain (and
/// `~/.local/bin` on POSIX) to `PATH` at spawn time, replacing the export
/// string `RemoteFlashskyaiCommandBuilder` used to hardcode.
///
/// Spawning stays behind the [PtySpawner] seam so tests need no Flutter
/// binding; spawn failures are logged and refused (the factory returns
/// `null`), never thrown through the server.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_pty_new/flutter_pty_new.dart' as pty;
import 'package:tp_sshd/tp_sshd.dart';

import '../../utils/logging/logger_utils.dart';
import '../cli/registry/installer/teampilot_node_install.dart';
import '../storage/app_storage.dart' show AppPaths;

/// The user's login shell, or `/bin/bash` when unknown. PowerShell on
/// Windows.
class EmbeddedShellSelection {
  EmbeddedShellSelection._();

  /// The shell executable for [platform] (`'windows'`, `'linux'`,
  /// `'macos'`): `powershell.exe` on Windows, `$SHELL` (`shellEnv`) or
  /// `/bin/bash` elsewhere.
  static String executable({required String platform, String? shellEnv}) {
    if (platform == 'windows') return 'powershell.exe';
    final shell = shellEnv?.trim() ?? '';
    return shell.isEmpty ? '/bin/bash' : shell;
  }

  /// The arguments to start the shell with (a clean `-NoLogo` PowerShell).
  static List<String> arguments({required String platform}) =>
      platform == 'windows' ? const ['-NoLogo'] : const [];
}

/// Spawn-environment construction for embedded processes: prepends the
/// managed Node toolchain bin directory to `PATH` so npm-installed CLI
/// shims (`#!/usr/bin/env node`) resolve.
class EmbeddedSpawnEnvironment {
  EmbeddedSpawnEnvironment._();

  /// The managed toolchain bin directory for the running platform, or
  /// `null` when the home environment variable is unavailable.
  ///
  /// POSIX mirrors the installer layout
  /// (`$HOME/.local/share/<app-data>/toolchain/node/current/bin` — the
  /// `current` symlink so glibc fallback versions resolve); Windows uses
  /// `%LOCALAPPDATA%\<app-data>\toolchain\node\<version>`, where `node.exe`
  /// and `npm.cmd` live at the version directory's root.
  static String? defaultToolchainBin({
    bool? isWindows,
    Map<String, String>? environment,
  }) {
    final windows = isWindows ?? Platform.isWindows;
    final env = environment ?? Platform.environment;
    if (windows) {
      final localAppData = env['LOCALAPPDATA'];
      if (localAppData == null || localAppData.isEmpty) return null;
      return <String>[
        localAppData,
        TeampilotNodeInstall.windowsToolchainNodeBase,
        TeampilotNodeInstall.version,
      ].join(r'\');
    }
    final home = env['HOME'];
    if (home == null || home.isEmpty) return null;
    return <String>[
      home,
      '.local',
      'share',
      AppPaths.teampilotAppDataDirName,
      'toolchain',
      'node',
      'current',
      'bin',
    ].join('/');
  }

  /// Returns a copy of [base] with [toolchainBin] (and `~/.local/bin` on
  /// POSIX — npm `--prefix ~/.local` shims) prepended to `PATH`, preserving
  /// the inherited entries. An empty [toolchainBin] skips the toolchain
  /// entry; the platform-appropriate separator (`;` on Windows) is used.
  static Map<String, String> mergeWithToolchainPath(
    Map<String, String> base, {
    required String toolchainBin,
    bool? isWindows,
  }) {
    final windows = isWindows ?? Platform.isWindows;
    final merged = Map<String, String>.of(base);
    final home = base['HOME'];
    final prepends = <String>[
      if (toolchainBin.isNotEmpty) toolchainBin,
      if (!windows && home != null && home.isNotEmpty) '$home/.local/bin',
    ];
    if (prepends.isEmpty) return merged;
    final inherited = base['PATH'] ?? '';
    merged['PATH'] = prepends
        .followedBy(inherited.isEmpty ? const <String>[] : [inherited])
        .join(windows ? ';' : ':');
    return merged;
  }
}

/// A process handle behind the [PtySpawner] seam: the slice of
/// flutter_pty's [pty.Pty] the embedded pty adapter consumes. Abstract so
/// tests can fake spawning without a Flutter binding.
abstract class PtyLike {
  Stream<Uint8List> get output;
  Future<int> get exitCode;
  void write(Uint8List data);
  void resize(int columns, int rows);
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]);
}

/// Spawns a process in a pseudo-terminal.
typedef PtySpawner =
    Future<PtyLike> Function({
      required String executable,
      required List<String> arguments,
      required Map<String, String> environment,
      required int columns,
      required int rows,
      String? workingDirectory,
    });

/// Builds the [SSHPtyFactory] for `shell` requests: spawns the OS-native
/// shell in a pty with the toolchain `PATH` injected and the dimensions the
/// client asked for. A working directory the client requested via
/// [SSHPtyDimensions.workingDirectoryEnv] scopes the shell (the variable is
/// consumed, not inherited). Spawn failures are logged and refused (`null`).
SSHPtyFactory embeddedPtyFactory({PtySpawner? spawner, String? toolchainBin}) {
  final spawn = spawner ?? _defaultPtySpawner;
  return (initial) async {
    final env = EmbeddedSpawnEnvironment.mergeWithToolchainPath(
      {...Platform.environment, ...initial.environment},
      toolchainBin:
          toolchainBin ?? EmbeddedSpawnEnvironment.defaultToolchainBin() ?? '',
    );
    final requestedCwd = env.remove(SSHPtyDimensions.workingDirectoryEnv);
    final cwd = requestedCwd == null || requestedCwd.isEmpty
        ? null
        : requestedCwd;
    final platform = Platform.operatingSystem;
    try {
      return _PtyLikeServerPty(
        await spawn(
          executable: EmbeddedShellSelection.executable(
            platform: platform,
            shellEnv: Platform.environment['SHELL'],
          ),
          arguments: EmbeddedShellSelection.arguments(platform: platform),
          environment: env,
          columns: initial.columns,
          rows: initial.rows,
          workingDirectory: cwd,
        ),
      );
    } on Object catch (error, stackTrace) {
      AppLogger.instance.w(
        'embedded shell: refused pty spawn',
        error: error,
        stackTrace: stackTrace,
      );
      return null;
    }
  };
}

/// Builds the [SSHProcessFactory] for structured `exec` requests: spawns
/// `argv` directly (never through a shell) in [cwd], with the toolchain
/// `PATH` injected. Spawn failures are logged and refused (`null`).
SSHProcessFactory embeddedProcessFactory({String? toolchainBin}) {
  return (argv, cwd, env) async {
    final merged = EmbeddedSpawnEnvironment.mergeWithToolchainPath(
      {...Platform.environment, ...env},
      toolchainBin:
          toolchainBin ?? EmbeddedSpawnEnvironment.defaultToolchainBin() ?? '',
    );
    try {
      return _ProcessServerProcessAdapter(
        await Process.start(
          argv.first,
          argv.skip(1).toList(),
          workingDirectory: cwd,
          environment: merged,
        ),
      );
    } on Object catch (error, stackTrace) {
      AppLogger.instance.w(
        'embedded exec: refused spawn of ${argv.first}',
        error: error,
        stackTrace: stackTrace,
      );
      return null;
    }
  };
}

/// Wraps a flutter_pty [pty.Pty] as a [PtyLike] — pure glue. Note the
/// resize argument order: [PtyLike.resize] is (columns, rows),
/// [pty.Pty.resize] is (rows, cols).
Future<PtyLike> _defaultPtySpawner({
  required String executable,
  required List<String> arguments,
  required Map<String, String> environment,
  required int columns,
  required int rows,
  String? workingDirectory,
}) async {
  final process = pty.Pty.start(
    executable,
    arguments: arguments,
    environment: environment,
    columns: columns,
    rows: rows,
    workingDirectory: workingDirectory,
  );
  return _FlutterPtyLike(process);
}

class _FlutterPtyLike implements PtyLike {
  _FlutterPtyLike(this._process);

  final pty.Pty _process;

  @override
  Stream<Uint8List> get output => _process.output;

  @override
  Future<int> get exitCode => _process.exitCode;

  @override
  void write(Uint8List data) => _process.write(data);

  @override
  void resize(int columns, int rows) => _process.resize(rows, columns);

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) =>
      _process.kill(signal);
}

/// A [pty.Pty] (or faked [PtyLike]) as an [SSHServerPty].
class _PtyLikeServerPty implements SSHServerPty {
  _PtyLikeServerPty(this._pty);

  final PtyLike _pty;
  late final _PtyStdinSink _stdin = _PtyStdinSink(_pty.write);

  /// RFC 4254 §6.9 signal names (without the `SIG` prefix) mapped to the
  /// signals the pty can be killed with.
  static const Map<String, ProcessSignal> _signals = {
    'INT': ProcessSignal.sigint,
    'TERM': ProcessSignal.sigterm,
    'HUP': ProcessSignal.sighup,
    'KILL': ProcessSignal.sigkill,
  };

  /// The pty's merged output. A pseudo-terminal has no separate stderr —
  /// the channel reports everything as stdout and no extended data.
  @override
  Stream<Uint8List> get stdout => _pty.output;

  @override
  Stream<Uint8List> get stderr => const Stream.empty();

  @override
  StreamSink<List<int>> get stdin => _stdin;

  @override
  Future<int> get exitCode => _pty.exitCode;

  @override
  void kill() => _pty.kill();

  @override
  void resize(int columns, int rows) => _pty.resize(columns, rows);

  @override
  void signal(String name) {
    final signal = _signals[name];
    if (signal == null) {
      AppLogger.instance.d('embedded pty: dropping unknown signal $name');
      return;
    }
    _pty.kill(signal);
  }
}

/// Forwards channel input into the pty. Closing does not kill the process —
/// a pty has no stdin to close; the channel's own teardown does.
class _PtyStdinSink implements StreamSink<List<int>> {
  _PtyStdinSink(this._write);

  final void Function(Uint8List data) _write;
  final _done = Completer<void>();
  bool _closed = false;

  @override
  void add(List<int> data) {
    if (_closed) return;
    _write(Uint8List.fromList(data));
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    await for (final data in stream) {
      add(data);
    }
  }

  @override
  Future<void> close() {
    if (!_closed) {
      _closed = true;
      _done.complete();
    }
    return _done.future;
  }

  @override
  Future<void> get done => _done.future;
}

/// A `Process.start` process as an [SSHServerProcess].
class _ProcessServerProcessAdapter implements SSHServerProcess {
  _ProcessServerProcessAdapter(this._process);

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
