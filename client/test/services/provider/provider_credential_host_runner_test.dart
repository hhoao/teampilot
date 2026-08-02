import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/host/host_one_shot_runner.dart';
import 'package:teampilot/services/host/host_process_starter.dart';
import 'package:teampilot/services/host/process_run_handle.dart';
import 'package:teampilot/services/provider/provider_credential_host_runner.dart';

class _FakeOneShotRunner implements HostOneShotRunner {
  _FakeOneShotRunner(this._result);

  final HostRunResult _result;

  @override
  Future<HostRunResult> run(HostRunRequest request) async => _result;
}

class _FailOneShotRunner implements HostOneShotRunner {
  @override
  Future<HostRunResult> run(HostRunRequest request) {
    throw StateError('one-shot should not be called');
  }
}

class _ScriptedProcessHandle implements ProcessRunHandle {
  _ScriptedProcessHandle({
    required List<List<int>> stdoutChunks,
    List<List<int>> stderrChunks = const [],
    this.exitCodeValue = 0,
  }) : _stdoutChunks = stdoutChunks,
       _stderrChunks = stderrChunks;

  final List<List<int>> _stdoutChunks;
  final List<List<int>> _stderrChunks;
  final int exitCodeValue;

  @override
  Future<int> get exitCode => Future.value(exitCodeValue);

  @override
  Stream<List<int>> get stdout => Stream.fromIterable(_stdoutChunks);

  @override
  Stream<List<int>> get stderr => Stream.fromIterable(_stderrChunks);

  @override
  void kill() {}
}

class _ScriptedStarter implements HostProcessStarter {
  _ScriptedStarter(
    this.stdoutChunks, {
    List<List<int>> stderrChunks = const [],
    this.exitCode = 0,
    this.startError,
  }) : _stderrChunks = stderrChunks;

  final List<List<int>> stdoutChunks;
  final List<List<int>> _stderrChunks;
  final int exitCode;
  final Object? startError;

  @override
  Future<ProcessRunHandle> start(HostRunRequest request) async {
    if (startError != null) throw startError!;
    return _ScriptedProcessHandle(
      stdoutChunks: stdoutChunks,
      stderrChunks: _stderrChunks,
      exitCodeValue: exitCode,
    );
  }
}

class _ThrowingStarter implements HostProcessStarter {
  _ThrowingStarter(this.error);

  final Object error;

  @override
  Future<ProcessRunHandle> start(HostRunRequest request) async {
    throw error;
  }
}

void main() {
  group('ProviderCredentialHostRunner.run', () {
    test('delegates to one-shot runner', () async {
      const expected = HostRunResult(
        exitCode: 0,
        stdout: 'ok',
        stderr: '',
      );
      final runner = ProviderCredentialHostRunner(
        oneShot: () => _FakeOneShotRunner(expected),
        streaming: () => _ThrowingStarter(StateError('no stream')),
      );

      final result = await runner.run(
        const HostRunRequest(executable: 'cursor-agent', arguments: ['logout']),
      );

      expect(result, expected);
    });
  });

  group('ProviderCredentialHostRunner.runLogin', () {
    test('opens preferred URL once and dedupes repeats', () async {
      final opened = <Uri>[];
      final runner = ProviderCredentialHostRunner(
        oneShot: () => _FailOneShotRunner(),
        streaming: () => _ScriptedStarter([
          utf8.encode(
            'Docs https://example.com/docs\n'
            'Login https://authenticator.cursor.sh/login?code=abc\n'
            'Again https://authenticator.cursor.sh/login?code=abc\n',
          ),
        ]),
        openUrl: (uri) async => opened.add(uri),
      );

      final result = await runner.runLogin(
        const HostRunRequest(executable: 'cursor-agent', arguments: ['login']),
      );

      expect(result.exitCode, 0);
      expect(opened.map((u) => u.host), ['authenticator.cursor.sh', 'example.com']);
      expect(result.stdout, contains('authenticator.cursor.sh'));
    });

    test('opens URL split across chunk boundary', () async {
      final opened = <Uri>[];
      final runner = ProviderCredentialHostRunner(
        oneShot: () => _FailOneShotRunner(),
        streaming: () => _ScriptedStarter([
          utf8.encode('Open https://auth.'),
          utf8.encode('cursor.sh/login\n'),
        ]),
        openUrl: (uri) async => opened.add(uri),
      );

      final result = await runner.runLogin(
        const HostRunRequest(executable: 'cursor-agent', arguments: ['login']),
      );

      expect(result.exitCode, 0);
      expect(opened.single.host, 'auth.cursor.sh');
    });

    test('opens URL printed only on stderr', () async {
      final opened = <Uri>[];
      final runner = ProviderCredentialHostRunner(
        oneShot: () => _FailOneShotRunner(),
        streaming: () => _ScriptedStarter(
          const [],
          stderrChunks: [
            utf8.encode('Visit https://claude.ai/oauth/authorize?x=1\n'),
          ],
        ),
        openUrl: (uri) async => opened.add(uri),
      );

      final result = await runner.runLogin(
        const HostRunRequest(executable: 'claude', arguments: ['auth', 'login']),
      );

      expect(result.exitCode, 0);
      expect(opened.single.host, 'claude.ai');
      expect(result.stderr, contains('claude.ai'));
      expect(result.stdout, isEmpty);
    });

    test('openUrl throw does not fail login when exit is 0', () async {
      final runner = ProviderCredentialHostRunner(
        oneShot: () => _FailOneShotRunner(),
        streaming: () => _ScriptedStarter([
          utf8.encode('https://authenticator.cursor.sh/login\n'),
        ]),
        openUrl: (uri) async => throw StateError('browser unavailable'),
      );

      final result = await runner.runLogin(
        const HostRunRequest(executable: 'cursor-agent', arguments: ['login']),
      );

      expect(result.exitCode, 0);
      expect(result.succeeded, isTrue);
    });

    test('wraps non-ProcessException start failures as ProcessException', () async {
      final runner = ProviderCredentialHostRunner(
        oneShot: () => _FailOneShotRunner(),
        streaming: () => _ThrowingStarter(StateError('ssh down')),
      );

      expect(
        () => runner.runLogin(
          const HostRunRequest(
            executable: '/root/.local/bin/cursor-agent',
            arguments: ['login'],
          ),
        ),
        throwsA(
          isA<ProcessException>()
              .having((e) => e.executable, 'executable', '/root/.local/bin/cursor-agent')
              .having((e) => e.arguments, 'arguments', ['login'])
              .having((e) => e.message, 'message', contains('ssh down')),
        ),
      );
    });

    test('opens complete URL at end of chunk before process exits', () async {
      final opened = <Uri>[];
      final handle = _LiveStdoutHandle();
      final runner = ProviderCredentialHostRunner(
        oneShot: () => _FailOneShotRunner(),
        streaming: () => _FixedHandleStarter(handle),
        openUrl: (uri) async => opened.add(uri),
      );

      final login = runner.runLogin(
        const HostRunRequest(executable: 'cursor-agent', arguments: ['login']),
      );

      handle.emit(
        utf8.encode(
          'Open a browser and navigate to this link: '
          'https://cursor.com/loginDeepControl?challenge=abc&uuid=1',
        ),
      );
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(
        opened,
        isNotEmpty,
        reason: 'URL must open while login process is still waiting',
      );
      expect(opened.single.host, 'cursor.com');

      await handle.finish(exitCode: 0);
      final result = await login;
      expect(result.exitCode, 0);
    });
  });
}

class _FixedHandleStarter implements HostProcessStarter {
  _FixedHandleStarter(this.handle);

  final ProcessRunHandle handle;

  @override
  Future<ProcessRunHandle> start(HostRunRequest request) async => handle;
}

class _LiveStdoutHandle implements ProcessRunHandle {
  final _stdout = StreamController<List<int>>();
  final _exit = Completer<int>();

  void emit(List<int> chunk) => _stdout.add(chunk);

  Future<void> finish({required int exitCode}) async {
    await _stdout.close();
    if (!_exit.isCompleted) _exit.complete(exitCode);
  }

  @override
  Future<int> get exitCode => _exit.future;

  @override
  Stream<List<int>> get stdout => _stdout.stream;

  @override
  Stream<List<int>> get stderr => const Stream.empty();

  @override
  void kill() {
    if (!_exit.isCompleted) _exit.complete(1);
  }
}
