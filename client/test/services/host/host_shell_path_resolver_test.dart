import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/host/host_shell_path_resolver.dart';

/// Minimal [Process] fake: controllable stdout payload, hang behavior, and a
/// `killed` flag so tests can assert timeout cleanup.
class _FakeShell implements Process {
  _FakeShell.success(String stdoutText)
    : _stdoutBytes = utf8.encode(stdoutText),
      _exitFuture = Future.value(0);

  _FakeShell.failure()
    : _stdoutBytes = const <int>[],
      _exitFuture = Future.value(1);

  _FakeShell.hanging()
    : _stdoutBytes = null,
      _exitFuture = Completer<int>().future;

  final List<int>? _stdoutBytes;
  final Future<int> _exitFuture;
  bool killed = false;

  @override
  Future<int> get exitCode => _exitFuture;

  @override
  Stream<List<int>> get stdout =>
      _stdoutBytes == null ? const Stream.empty() : Stream.value(_stdoutBytes);

  @override
  Stream<List<int>> get stderr => const Stream.empty();

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    killed = true;
    return true;
  }

  @override
  int get pid => 424242;

  @override
  IOSink get stdin => throw UnimplementedError();
}

void main() {
  setUp(HostShellPathResolver.resetForTest);
  tearDown(HostShellPathResolver.resetForTest);

  group('parseMarkerOutput', () {
    test('extracts PATH after marker', () {
      expect(
        HostShellPathResolver.parseMarkerOutput(
          '${HostShellPathResolver.marker}/usr/bin:/opt/homebrew/bin',
        ),
        '/usr/bin:/opt/homebrew/bin',
      );
    });

    test('uses content after the LAST marker, truncates lines, drops junk',
        () {
      const m = HostShellPathResolver.marker;
      final out =
          'nvm banner\r\n\$ PS1-active ${m}junk\nagain ${m}usr/relative\n'
          '$m/usr/bin:/bin tail';
      expect(HostShellPathResolver.parseMarkerOutput(out), '/usr/bin');
    });

    test('returns null when every absolute entry contains whitespace (fish)',
        () {
      const m = HostShellPathResolver.marker;
      // fish joins $PATH with spaces → one giant space-containing "entry".
      expect(
        HostShellPathResolver.parseMarkerOutput(
          '$m/usr/bin /opt/homebrew/bin ~/.local/bin',
        ),
        isNull,
      );
    });

    test('drops whitespace entries but keeps clean absolute neighbors', () {
      const m = HostShellPathResolver.marker;
      expect(
        HostShellPathResolver.parseMarkerOutput('$m/a b:/usr/bin'),
        '/usr/bin',
      );
    });

    test('rejects missing marker, empty, and non-absolute results', () {
      const m = HostShellPathResolver.marker;
      expect(HostShellPathResolver.parseMarkerOutput('no marker'), isNull);
      expect(HostShellPathResolver.parseMarkerOutput('$m   '), isNull);
      expect(
        HostShellPathResolver.parseMarkerOutput('${m}relative/path'),
        isNull,
      );
    });

    test('round-trips non-ASCII directory names', () {
      const m = HostShellPathResolver.marker;
      expect(
        HostShellPathResolver.parseMarkerOutput(
          '$m/home/李明/.local/bin:/usr/bin',
        ),
        '/home/李明/.local/bin:/usr/bin',
      );
    });
  });

  group('shellCandidates', () {
    test('uses \$SHELL path first, then zsh, then bash, deduped by basename',
        () {
      HostShellPathResolver.debugShellOverride = () => '/bin/bash';
      expect(HostShellPathResolver.shellCandidates(), ['/bin/bash', 'zsh']);
    });

    test('does not also spawn basename zsh when \$SHELL is already zsh', () {
      HostShellPathResolver.debugShellOverride = () => '/usr/bin/zsh';
      expect(HostShellPathResolver.shellCandidates(), ['/usr/bin/zsh', 'bash']);
    });

    test('prepends a non-fallback \$SHELL path before zsh and bash', () {
      HostShellPathResolver.debugShellOverride = () => '/usr/local/bin/fish';
      expect(
        HostShellPathResolver.shellCandidates(),
        ['/usr/local/bin/fish', 'zsh', 'bash'],
      );
    });

    test('falls back to zsh then bash when \$SHELL is empty', () {
      HostShellPathResolver.debugShellOverride = () => '';
      expect(HostShellPathResolver.shellCandidates(), ['zsh', 'bash']);
    });
  });

  group('resolve', () {
    test('does not probe zsh when \$SHELL bash succeeds', () async {
      HostShellPathResolver.debugShellOverride = () => '/bin/bash';
      final invoked = <String>[];
      final result = await HostShellPathResolver.resolve(
        posixPlatformOverride: true,
        starter: (executable, arguments) async {
          invoked.add(executable);
          return _FakeShell.success('${HostShellPathResolver.marker}/b/bin');
        },
      );
      expect(result, '/b/bin');
      expect(invoked, ['/bin/bash']);
    });

    test('tries \$SHELL path first, then zsh, then stops at first hit',
        () async {
      HostShellPathResolver.debugShellOverride = () => '/usr/local/bin/fish';
      final invoked = <String>[];
      final result = await HostShellPathResolver.resolve(
        posixPlatformOverride: true,
        starter: (executable, arguments) async {
          invoked.add(executable);
          if (executable == '/usr/local/bin/fish') {
            return _FakeShell.success('fish noise'); // parses to null
          }
          return _FakeShell.success('${HostShellPathResolver.marker}/z/bin');
        },
      );
      expect(result, '/z/bin');
      expect(invoked, ['/usr/local/bin/fish', 'zsh']);
    });

    test('kills every shell when each times out', () async {
      // Override SHELL so candidates dedupe to ['/bin/zsh', 'bash'],
      // regardless of the host environment.
      HostShellPathResolver.debugShellOverride = () => '/bin/zsh';
      final shells = <String, _FakeShell>{
        '/bin/zsh': _FakeShell.hanging(),
        'bash': _FakeShell.hanging(),
      };
      final result = await HostShellPathResolver.resolve(
        posixPlatformOverride: true,
        timeout: const Duration(milliseconds: 10),
        starter: (executable, arguments) async {
          final shell = shells[executable];
          if (shell == null) {
            fail('unexpected executable: $executable');
          }
          return shell;
        },
      );
      expect(result, isNull);
      expect(shells['/bin/zsh']!.killed, isTrue);
      expect(shells['bash']!.killed, isTrue);
    });

    test('falls through a hanging first shell to the next one', () async {
      HostShellPathResolver.debugShellOverride = () => '/bin/zsh'; // → /bin/zsh, bash
      final zsh = _FakeShell.hanging();
      final result = await HostShellPathResolver.resolve(
        posixPlatformOverride: true,
        timeout: const Duration(milliseconds: 10),
        starter: (executable, arguments) async =>
            executable == '/bin/zsh'
                ? zsh
                : _FakeShell.success(
                    '${HostShellPathResolver.marker}/b/bin',
                  ),
      );
      expect(result, '/b/bin');
      expect(zsh.killed, isTrue);
    });

    test('round-trips non-ASCII dirs through real utf8 bytes', () async {
      final result = await HostShellPathResolver.resolve(
        posixPlatformOverride: true,
        starter: (executable, arguments) async => _FakeShell.success(
          '${HostShellPathResolver.marker}/home/李明/.local/bin:/usr/bin',
        ),
      );
      expect(result, '/home/李明/.local/bin:/usr/bin');
    });

    test('treats nonzero exit as probe failure', () async {
      HostShellPathResolver.debugShellOverride = () => '/bin/zsh'; // → /bin/zsh, bash
      final result = await HostShellPathResolver.resolve(
        posixPlatformOverride: true,
        starter: (executable, arguments) async => executable == '/bin/zsh'
            ? _FakeShell.failure()
            : _FakeShell.success('${HostShellPathResolver.marker}/b/bin'),
      );
      expect(result, '/b/bin');
    });

    test('caches success without re-running shells', () async {
      var calls = 0;
      await HostShellPathResolver.resolve(
        posixPlatformOverride: true,
        starter: (executable, arguments) async {
          calls++;
          return _FakeShell.success('${HostShellPathResolver.marker}/c/bin');
        },
      );
      final second = await HostShellPathResolver.resolve(
        posixPlatformOverride: true,
        starter: (executable, arguments) async {
          calls++;
          return _FakeShell.success('${HostShellPathResolver.marker}/other');
        },
      );
      expect(second, '/c/bin');
      expect(calls, 1);
      expect(HostShellPathResolver.cachedPath, '/c/bin');
    });

    test('caches failure as null without retrying', () async {
      // Deterministic candidates: ['/bin/zsh', 'bash'] regardless of host SHELL.
      HostShellPathResolver.debugShellOverride = () => '/bin/zsh';
      var calls = 0;
      final result = await HostShellPathResolver.resolve(
        posixPlatformOverride: true,
        starter: (executable, arguments) async {
          calls++;
          return _FakeShell.success('garbage without marker');
        },
      );
      expect(result, isNull);
      expect(calls, 2); // zsh + bash both probed
      final again = await HostShellPathResolver.resolve(
        posixPlatformOverride: true,
        starter: (executable, arguments) async {
          calls++;
          fail('must not re-run');
        },
      );
      expect(again, isNull);
      expect(calls, 2); // cached failure → no additional probes
    });

    test('non-POSIX override short-circuits to null', () async {
      final result = await HostShellPathResolver.resolve(
        posixPlatformOverride: false,
        starter: (executable, arguments) async => fail('must not spawn'),
      );
      expect(result, isNull);
      expect(HostShellPathResolver.cachedPath, isNull);
    });
  });

  test('fallbackCandidateDirs includes homebrew, usr/local and ~/.local/bin',
      () {
    final dirs = HostShellPathResolver.fallbackCandidateDirs();
    expect(dirs.take(2), ['/opt/homebrew/bin', '/usr/local/bin']);
    expect(dirs.where((d) => d.endsWith('/.local/bin')), isNotEmpty);
  });
}
