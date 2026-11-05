import 'dart:io';

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
