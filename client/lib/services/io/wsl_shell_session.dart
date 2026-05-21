import 'dart:async';
import 'dart:convert';
import 'dart:collection';
import 'dart:io';

/// Persistent WSL bash loop — one [wsl.exe] process, many commands via stdin.
///
/// Avoids spawning a new WSL process for every filesystem operation (~140ms each).
class WslShellSession {
  WslShellSession({String? distro}) : _distro = distro?.trim();

  final String? _distro;

  Process? _process;
  StreamSubscription<String>? _stdoutSub;
  StreamSubscription<String>? _stderrSub;

  final Queue<_PendingRun> _queue = Queue();
  _PendingRun? _active;
  var _starting = false;
  var _pumping = false;

  static const _loopScript = r'''
while IFS= read -r payload || [ -n "$payload" ]; do
  [ -z "$payload" ] && continue
  case "$payload" in
    __TP_QUIT__) exit 0 ;;
  esac
  set +e
  eval "$(printf '%s' "$payload" | base64 -d)"
  rc=$?
  set -e
  printf '__TPRC__:%s\n' "$rc"
done
''';

  List<String> get _wslArgs {
    final distro = _distro;
    if (distro == null || distro.isEmpty) return const [];
    return ['-d', distro];
  }

  Future<({int exitCode, String stdout, String stderr})> run(String script) {
    final pending = _PendingRun(script);
    _queue.add(pending);
    unawaited(_pumpQueue());
    return pending.completer.future;
  }

  Future<void> _pumpQueue() async {
    if (_pumping) return;
    _pumping = true;
    try {
      if (_queue.isEmpty) return;
      await _ensureStarted();
      while (_queue.isNotEmpty && _process != null) {
        _active = _queue.removeFirst();
        final payload = base64.encode(utf8.encode(_active!.script));
        _process!.stdin.writeln(payload);
        await _process!.stdin.flush();
        await _active!.completer.future;
        _active = null;
        if (_process == null) break;
      }
    } finally {
      _pumping = false;
      if (_queue.isNotEmpty) {
        unawaited(_pumpQueue());
      }
    }
  }

  Future<void> _ensureStarted() async {
    if (_process != null || _starting) {
      while (_starting) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      return;
    }
    _starting = true;
    try {
      final proc = await Process.start(
        'wsl.exe',
        [..._wslArgs, 'bash', '--noprofile', '--norc', '-c', _loopScript],
        mode: ProcessStartMode.normal,
      );
      _process = proc;
      _stdoutSub = proc.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(_onStdoutLine, onError: _onStreamError);
      _stderrSub = proc.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(_onStderrLine, onError: (_) {});
      proc.exitCode.then((_) => _handleProcessExit());
    } finally {
      _starting = false;
    }
  }

  void _onStdoutLine(String line) {
    final active = _active;
    if (active == null) return;
    if (line.startsWith('__TPRC__:')) {
      final rc = int.tryParse(line.substring(7)) ?? 1;
      if (!active.completer.isCompleted) {
        active.completer.complete((
          exitCode: rc,
          stdout: active.stdout.toString(),
          stderr: active.stderr.toString(),
        ));
      }
      return;
    }
    if (active.stdout.isNotEmpty) active.stdout.writeln();
    active.stdout.write(line);
  }

  void _onStderrLine(String line) {
    final active = _active;
    if (active == null) return;
    if (active.stderr.isNotEmpty) active.stderr.writeln();
    active.stderr.write(line);
  }

  void _onStreamError(Object error, StackTrace stackTrace) {
    _failActive(StateError('WSL stdout stream error: $error'));
    _handleProcessExit();
  }

  void _handleProcessExit() {
    _stdoutSub?.cancel();
    _stderrSub?.cancel();
    _stdoutSub = null;
    _stderrSub = null;
    _process = null;
    _failActive(StateError('WSL shell session exited unexpectedly'));
    while (_queue.isNotEmpty) {
      final pending = _queue.removeFirst();
      if (!pending.completer.isCompleted) {
        pending.completer.completeError(
          StateError('WSL shell session is not running'),
        );
      }
    }
  }

  void _failActive(Object error) {
    final active = _active;
    _active = null;
    if (active != null && !active.completer.isCompleted) {
      active.completer.completeError(error);
    }
  }

  Future<void> close() async {
    final proc = _process;
    if (proc != null) {
      try {
        proc.stdin.writeln('__TP_QUIT__');
        await proc.stdin.flush();
      } on Object {
        proc.kill();
      }
    }
    await _stdoutSub?.cancel();
    await _stderrSub?.cancel();
    _stdoutSub = null;
    _stderrSub = null;
    _process = null;
    _failActive(StateError('WSL shell session closed'));
    while (_queue.isNotEmpty) {
      final pending = _queue.removeFirst();
      if (!pending.completer.isCompleted) {
        pending.completer.completeError(
          StateError('WSL shell session closed'),
        );
      }
    }
  }
}

class _PendingRun {
  _PendingRun(this.script);

  final String script;
  final stdout = StringBuffer();
  final stderr = StringBuffer();
  final completer = Completer<({int exitCode, String stdout, String stderr})>();
}
