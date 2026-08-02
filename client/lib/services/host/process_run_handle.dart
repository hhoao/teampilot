import 'dart:async';
import 'dart:io';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart';

/// Abstraction over a spawned child process for tests and production.
abstract class ProcessRunHandle {
  Future<int> get exitCode;
  Stream<List<int>> get stdout;
  Stream<List<int>> get stderr;
  void kill();
}

/// [ProcessRunHandle] over a local [Process] from [Process.start].
class LocalProcessRunHandle implements ProcessRunHandle {
  LocalProcessRunHandle(this._process);

  final Process _process;

  @override
  Future<int> get exitCode => _process.exitCode;

  @override
  Stream<List<int>> get stdout => _process.stdout;

  @override
  Stream<List<int>> get stderr => _process.stderr;

  @override
  void kill() => _process.kill();
}

/// [ProcessRunHandle] over a dartssh2 [SSHSession] (non-PTY exec).
class SshProcessRunHandle implements ProcessRunHandle {
  SshProcessRunHandle(this._session);

  final SSHSession _session;

  @override
  Future<int> get exitCode async {
    await _session.done;
    return _session.exitCode ?? 0;
  }

  @override
  Stream<List<int>> get stdout => _session.stdout.map(_asList);

  @override
  Stream<List<int>> get stderr => _session.stderr.map(_asList);

  @override
  void kill() {
    try {
      _session.kill(SSHSignal.KILL);
    } catch (_) {
      _session.close();
    }
  }

  static List<int> _asList(Uint8List data) => data;
}
