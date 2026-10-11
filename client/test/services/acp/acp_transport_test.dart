import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/acp/acp_process_transport.dart';
import 'package:teampilot/services/acp/acp_transport.dart';

void main() {
  group('NdjsonDecoder', () {
    test('NDJSON decoder splits frames and buffers partial chunks', () async {
      final decoder = NdjsonDecoder();
      final controller = StreamController<Uint8List>();
      final frames = decoder.decode(controller.stream).toList();
      controller.add(utf8.encode('{"a":1}\n{"b"'));
      await Future<void>.delayed(Duration.zero);
      controller.add(utf8.encode(':2}\n{"c":3}'));
      await Future<void>.delayed(Duration.zero);
      controller.add(utf8.encode('\n'));
      await controller.close();
      expect(await frames, ['{"a":1}', '{"b":2}', '{"c":3}']);
    });

    test('emits trailing frame without newline when stream ends', () async {
      final decoder = NdjsonDecoder();
      final controller = StreamController<Uint8List>();
      final frames = decoder.decode(controller.stream).toList();
      controller.add(utf8.encode('{"a":1}\n{"b":2}'));
      await controller.close();
      expect(await frames, ['{"a":1}', '{"b":2}']);
    });

    test(
      'decodes multi-byte UTF-8 split inside a character across chunks',
      () async {
        final decoder = NdjsonDecoder();
        final controller = StreamController<Uint8List>();
        final frames = decoder.decode(controller.stream).toList();
        final bytes = utf8.encode('{"msg":"你好"}\n');
        // '你' encodes to E4 BD A0 and '好' to E5 A5 BD. Split after the
        // first byte of '你' (offset 9) and after the second byte of '好'
        // (offset 13) so both chunk boundaries fall mid-character.
        controller.add(Uint8List.fromList(bytes.sublist(0, 9)));
        await Future<void>.delayed(Duration.zero);
        controller.add(Uint8List.fromList(bytes.sublist(9, 13)));
        await Future<void>.delayed(Duration.zero);
        controller.add(Uint8List.fromList(bytes.sublist(13)));
        await controller.close();
        final result = await frames;
        expect(result, ['{"msg":"你好"}']);
        expect(result.single.contains('\u{FFFD}'), isFalse);
      },
    );

    test('skips empty lines between frames', () async {
      final decoder = NdjsonDecoder();
      final controller = StreamController<Uint8List>();
      final frames = decoder.decode(controller.stream).toList();
      controller.add(utf8.encode('{"a":1}\n\n{"b":2}\n\n'));
      await controller.close();
      expect(await frames, ['{"a":1}', '{"b":2}']);
    });
  });

  group('AcpProcessTransport.stderr', () {
    test('invokes onStderr and fans out to the stderr stream', () async {
      final callbackChunks = <List<int>>[];
      final process = _FakeProcess();
      final transport = AcpProcessTransport(
        process: process,
        onStderr: callbackChunks.add,
      );
      final streamChunks = <List<int>>[];
      final subscription = transport.stderr.listen(streamChunks.add);
      process.emitStderr(utf8.encode('boom'));
      await Future<void>.delayed(Duration.zero);
      await subscription.cancel();
      process.exitWith(0);
      await transport.close();
      expect(utf8.decode(callbackChunks.single), 'boom');
      expect(utf8.decode(streamChunks.single), 'boom');
    });
  });

  group('AcpProcessTransport.close', () {
    test('SIGTERM then process exits within timeout', () async {
      final process = _FakeProcess();
      final transport = AcpProcessTransport(
        process: process,
        onStderr: (_) {},
        gracefulShutdownTimeout: const Duration(seconds: 5),
      );
      expect(transport.isClosed, isFalse);
      await transport.close();
      expect(process.killSignals, [ProcessSignal.sigterm]);
      expect(process.stdinClosed, isTrue);
      expect(transport.isClosed, isTrue);
    });

    test('SIGKILL after timeout when process ignores SIGTERM', () async {
      final process = _FakeProcess()..honorsSigterm = false;
      final transport = AcpProcessTransport(
        process: process,
        onStderr: (_) {},
        gracefulShutdownTimeout: const Duration(milliseconds: 50),
      );
      await transport.close();
      expect(process.killSignals, [
        ProcessSignal.sigterm,
        ProcessSignal.sigkill,
      ]);
      expect(transport.isClosed, isTrue);
    });

    test('close is idempotent', () async {
      final process = _FakeProcess();
      final transport = AcpProcessTransport(
        process: process,
        onStderr: (_) {},
        gracefulShutdownTimeout: const Duration(milliseconds: 50),
      );
      await transport.close();
      await transport.close();
      expect(process.killSignals, [ProcessSignal.sigterm]);
    });

    test(
      'mergeAcpProcessEnvironment drops empty values so Official OAuth is not API-key mode',
      () {
        final merged = mergeAcpProcessEnvironment(
          const {
            'CLAUDE_CONFIG_DIR': '/runtime/s1/claude',
            'ANTHROPIC_API_KEY': '',
            'ANTHROPIC_AUTH_TOKEN': '',
            'ANTHROPIC_BASE_URL': '',
            'CCGUI_CLI_LOGIN_AUTHORIZED': '1',
          },
          parent: const {
            'PATH': '/usr/bin',
            'ANTHROPIC_API_KEY': 'parent-key',
            'HOME': '/home/me',
          },
        );
        expect(merged['CLAUDE_CONFIG_DIR'], '/runtime/s1/claude');
        expect(merged['CCGUI_CLI_LOGIN_AUTHORIZED'], '1');
        expect(merged['PATH'], '/usr/bin');
        expect(merged['HOME'], '/home/me');
        expect(merged.containsKey('ANTHROPIC_API_KEY'), isFalse);
        expect(merged.containsKey('ANTHROPIC_AUTH_TOKEN'), isFalse);
        expect(merged.containsKey('ANTHROPIC_BASE_URL'), isFalse);
      },
    );

    test(
      'start omits empty ANTHROPIC_API_KEY from the child process',
      () async {
        const marker = 'ACP_ENV_PROBE';
        final transport = await AcpProcessTransport.start(
          executable: 'sh',
          args: const [
            '-c',
            r'if [ -z "${ANTHROPIC_API_KEY+x}" ]; then echo "$MARKER=ABSENT"; else echo "$MARKER=PRESENT"; fi',
          ],
          environment: {
            'PATH': Platform.environment['PATH'] ?? '/usr/bin',
            'MARKER': marker,
            'ANTHROPIC_API_KEY': '',
            'CLAUDE_CONFIG_DIR': '/tmp/claude-acp',
          },
          workingDirectory: Directory.systemTemp.path,
        );
        final lines = <String>[];
        final done = Completer<void>();
        late final StreamSubscription<String> subscription;
        subscription = NdjsonDecoder()
            .decode(transport.input)
            .listen(lines.add, onDone: done.complete);
        await done.future.timeout(const Duration(seconds: 5));
        await subscription.cancel();
        await transport.close();
        expect(lines.join('\n'), contains('$marker=ABSENT'));
      },
      skip: Platform.isWindows ? 'spawns POSIX sh' : false,
      timeout: const Timeout(Duration(seconds: 15)),
    );

    test(
      'start uses Process.start without a shell',
      () async {
        // `cat` echoes stdin, so a frame written comes back on stdout.
        final transport = await AcpProcessTransport.start(
          executable: 'cat',
          args: const [],
          environment: Platform.environment,
          workingDirectory: Directory.systemTemp.path,
        );
        final received = <String>[];
        final firstFrame = Completer<String>();
        late final StreamSubscription<String> subscription;
        subscription = NdjsonDecoder().decode(transport.input).listen((line) {
          received.add(line);
          if (!firstFrame.isCompleted) firstFrame.complete(line);
        });
        transport.write('{"ping":1}');
        final echoed = await firstFrame.future.timeout(
          const Duration(seconds: 5),
        );
        await subscription.cancel();
        await transport.close();
        expect(echoed, '{"ping":1}');
        expect(received, ['{"ping":1}']);
      },
      skip: Platform.isWindows ? 'spawns POSIX `cat`' : false,
      timeout: const Timeout(Duration(seconds: 15)),
    );
  });
}

/// Minimal [Process] fake: records signals, exits when killed hard.
class _FakeProcess implements Process {
  final StreamController<List<int>> _stdout =
      StreamController<List<int>>.broadcast();
  final StreamController<List<int>> _stderr =
      StreamController<List<int>>.broadcast();
  final Completer<int> _exitCode = Completer<int>();

  final List<ProcessSignal> killSignals = [];
  bool stdinClosed = false;

  void exitWith(int code) {
    if (!_exitCode.isCompleted) _exitCode.complete(code);
  }

  void emitStderr(List<int> data) {
    _stderr.add(data);
  }

  @override
  Future<int> get exitCode => _exitCode.future;

  /// Whether the fake honors SIGTERM (default: yes, like a well-behaved
  /// agent); set false to force the SIGKILL escalation path.
  bool honorsSigterm = true;

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    killSignals.add(signal);
    if (signal == ProcessSignal.sigkill) {
      // A real process cannot ignore SIGKILL.
      exitWith(-9);
    } else if (signal == ProcessSignal.sigterm && honorsSigterm) {
      exitWith(-15);
    }
    return true;
  }

  @override
  int get pid => 4194304 + killSignals.length; // Valid but unallocated PID.

  @override
  Stream<List<int>> get stderr => _stderr.stream;

  @override
  Stream<List<int>> get stdout => _stdout.stream;

  @override
  IOSink get stdin => _FakeStdin(() => stdinClosed = true);

  @override
  String toString() => '_FakeProcess(pid: $pid)';
}

class _FakeStdin implements IOSink {
  _FakeStdin(this._onClose);
  final void Function() _onClose;

  @override
  Encoding encoding = utf8;

  @override
  void add(List<int> data) {}

  @override
  void write(Object? object) {}

  @override
  void writeln([Object? object = '', String? sep = '\n']) {}

  @override
  void writeAll(Iterable<dynamic> objects, [String sep = '']) {}

  @override
  void writeCharCode(int charCode) {}

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future<void> addStream(Stream<List<int>> stream) async {}

  @override
  Future<void> get done async {}

  @override
  Future<void> flush() async {}

  @override
  Future<void> close() async => _onClose();
}
