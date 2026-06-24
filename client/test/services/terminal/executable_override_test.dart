import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/terminal/terminal_session.dart';
import 'package:teampilot/services/terminal/terminal_transport.dart';

/// B2: an off-home member's launch uses the CLI path preflight located on the
/// work machine — TerminalSession.connect(executableOverride:) is the seam the
/// launch passes `PreflightResult.remoteCliPath` through. Home members pass null
/// and keep the session's resolved executable (zero change).
class _FakeTransport implements TerminalTransport {
  final outputController = StreamController<Uint8List>.broadcast();
  final doneCompleter = Completer<int>();
  @override
  Stream<Uint8List> get output => outputController.stream;
  @override
  Future<int> get done => doneCompleter.future;
  @override
  void close() {
    if (!doneCompleter.isCompleted) doneCompleter.complete(0);
  }

  @override
  void resize(int rows, int columns) {}
  @override
  void write(Uint8List data) {}
}

String _validExecutable(List<String> candidates) {
  for (final c in candidates) {
    if (File(c).existsSync()) return c;
  }
  return Platform.resolvedExecutable;
}

void main() {
  final base = _validExecutable(['/bin/sh', '/usr/bin/true', '/bin/true']);
  final remote = _validExecutable(['/usr/bin/true', '/bin/true', '/bin/sh']);

  ({TerminalSession session, List<String> spawned}) build() {
    final spawned = <String>[];
    final session = TerminalSession(
      executable: base,
      transportStarter: (
        executable, {
        required arguments,
        required workingDirectory,
        required columns,
        required rows,
        environment,
      }) {
        spawned.add(executable);
        return Future.value(_FakeTransport());
      },
    );
    return (session: session, spawned: spawned);
  }

  test('executableOverride spawns the remote CLI path (off-home member)',
      () async {
    final b = build();
    addTearDown(b.session.dispose);
    b.session.connect(
      workingDirectory: Directory.systemTemp.path,
      executableOverride: remote,
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(b.spawned, isNotEmpty);
    expect(b.spawned.first, remote);
  });

  test('no override spawns the session executable (home member, zero change)',
      () async {
    final b = build();
    addTearDown(b.session.dispose);
    b.session.connect(workingDirectory: Directory.systemTemp.path);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(b.spawned, isNotEmpty);
    expect(b.spawned.first, base);
  });
}
