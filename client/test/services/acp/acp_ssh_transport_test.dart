import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/acp/acp_ssh_transport.dart';

class _FakeAcpSshChannel implements AcpSshChannel {
  final stdoutController = StreamController<Uint8List>();
  final stderrController = StreamController<Uint8List>();
  final exitCompleter = Completer<int>();
  final written = <String>[];
  bool stdinClosed = false;
  bool killed = false;
  bool disposed = false;

  /// When false, [kill] does NOT complete the exit future — models a remote
  /// process that ignores the graceful path until SIGKILL.
  bool exitOnKill = true;

  @override
  Stream<Uint8List> get stdout => stdoutController.stream;

  @override
  Stream<Uint8List> get stderr => stderrController.stream;

  @override
  Future<int> get exitCode => exitCompleter.future;

  @override
  void write(Uint8List data) => written.add(utf8.decode(data));

  @override
  Future<void> closeStdin() async => stdinClosed = true;

  @override
  void kill() {
    killed = true;
    if (exitOnKill && !exitCompleter.isCompleted) exitCompleter.complete(137);
  }

  @override
  void dispose() => disposed = true;

  void finish(int code) {
    if (!exitCompleter.isCompleted) exitCompleter.complete(code);
  }
}

void main() {
  test('write appends a newline-terminated frame', () {
    final channel = _FakeAcpSshChannel();
    final transport = AcpSshTransport(channel: channel, onStderr: null);
    transport.write('{"jsonrpc":"2.0"}');
    expect(channel.written, ['{"jsonrpc":"2.0"}\n']);
  });

  test('input forwards remote stdout bytes', () async {
    final channel = _FakeAcpSshChannel();
    final transport = AcpSshTransport(channel: channel, onStderr: null);
    final seen = <int>[];
    final sub = transport.input.listen(seen.addAll);
    channel.stdoutController.add(Uint8List.fromList([1, 2, 3]));
    await Future<void>.delayed(Duration.zero);
    expect(seen, [1, 2, 3]);
    await sub.cancel();
  });

  test('stderr stays separate and reaches onStderr and the stderr stream',
      () async {
    final channel = _FakeAcpSshChannel();
    final onStderr = <int>[];
    final transport = AcpSshTransport(
      channel: channel,
      onStderr: onStderr.addAll,
    );
    final seenStderr = <int>[];
    final sub = transport.stderr.listen(seenStderr.addAll);
    channel.stderrController.add(Uint8List.fromList([9, 8]));
    await Future<void>.delayed(Duration.zero);
    expect(onStderr, [9, 8]);
    expect(seenStderr, [9, 8]);
    await sub.cancel();
  });

  test('close sends stdin EOF, waits for exit, disposes without killing', () async {
    final channel = _FakeAcpSshChannel();
    final transport = AcpSshTransport(
      channel: channel,
      onStderr: null,
      gracefulShutdownTimeout: const Duration(milliseconds: 200),
    );
    final closing = transport.close();
    channel.finish(0);
    await closing;
    expect(channel.stdinClosed, isTrue);
    expect(channel.killed, isFalse);
    expect(channel.disposed, isTrue);
    expect(transport.isClosed, isTrue);
  });

  test('close escalates to kill when the remote ignores EOF', () async {
    final channel = _FakeAcpSshChannel()..exitOnKill = false;
    final transport = AcpSshTransport(
      channel: channel,
      onStderr: null,
      gracefulShutdownTimeout: const Duration(milliseconds: 20),
    );
    final closing = transport.close();
    // First timeout fires, kill() runs and (exitOnKill=false) does not finish.
    await Future<void>.delayed(const Duration(milliseconds: 60));
    channel.finish(137);
    await closing;
    expect(channel.killed, isTrue);
    expect(channel.disposed, isTrue);
  });

  test('write after close is a no-op', () async {
    final channel = _FakeAcpSshChannel();
    final transport = AcpSshTransport(channel: channel, onStderr: null);
    final closing = transport.close();
    channel.finish(0);
    await closing;
    transport.write('late');
    expect(channel.written, isEmpty);
  });
}
