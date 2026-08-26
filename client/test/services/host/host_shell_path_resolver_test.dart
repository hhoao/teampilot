import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/host/host_shell_path_resolver.dart';

void main() {
  setUp(HostShellPathResolver.resetForTest);
  tearDown(HostShellPathResolver.resetForTest);

  ProcessResult ok(String stdout) => ProcessResult(0, 0, stdout, '');

  group('parseMarkerOutput', () {
    test('extracts PATH after marker', () {
      expect(
        HostShellPathResolver.parseMarkerOutput(
          '${HostShellPathResolver.marker}/usr/bin:/opt/homebrew/bin',
        ),
        '/usr/bin:/opt/homebrew/bin',
      );
    });

    test('uses content after the LAST marker and truncates at line breaks', () {
      const m = HostShellPathResolver.marker;
      final out =
          'nvm banner\r\n\$ PS1-active ${m}junk\nagain ${m}usr/relative\n'
          '$m/usr/bin:/bin tail';
      expect(HostShellPathResolver.parseMarkerOutput(out), '/usr/bin:/bin tail');
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
  });

  group('resolve', () {
    test('tries \$SHELL basename first, then zsh, then stops at first hit',
        () async {
      HostShellPathResolver.debugShellOverride = () => '/usr/local/bin/fish';
      final invoked = <String>[];
      final result = await HostShellPathResolver.resolve(
        posixPlatformOverride: true,
        runner: (executable, arguments, {stdoutEncoding, stderrEncoding}) {
          invoked.add(executable);
          if (executable == 'fish') {
            return Future.value(ok('fish noise')); // parses to null → continue
          }
          return Future.value(ok('${HostShellPathResolver.marker}/z/bin'));
        },
      );
      expect(result, '/z/bin');
      expect(invoked, ['fish', 'zsh']);
    });

    test('returns null when every shell times out', () async {
      // Override SHELL so candidates dedupe to exactly ['zsh', 'bash'],
      // regardless of the host environment.
      HostShellPathResolver.debugShellOverride = () => '/bin/zsh';
      final result = await HostShellPathResolver.resolve(
        posixPlatformOverride: true,
        timeout: const Duration(milliseconds: 10),
        runner: (executable, arguments, {stdoutEncoding, stderrEncoding}) =>
            Completer<ProcessResult>().future,
      );
      expect(result, isNull);
    });

    test('falls through a hanging first shell to the next one', () async {
      HostShellPathResolver.debugShellOverride = () => '/bin/zsh'; // → zsh,bash
      final result = await HostShellPathResolver.resolve(
        posixPlatformOverride: true,
        timeout: const Duration(milliseconds: 10),
        runner: (executable, arguments, {stdoutEncoding, stderrEncoding}) {
          if (executable == 'zsh') return Completer<ProcessResult>().future;
          return Future.value(ok('${HostShellPathResolver.marker}/b/bin'));
        },
      );
      expect(result, '/b/bin');
    });

    test('caches success without re-running shells', () async {
      var calls = 0;
      await HostShellPathResolver.resolve(
        posixPlatformOverride: true,
        runner: (executable, arguments, {stdoutEncoding, stderrEncoding}) {
          calls++;
          return Future.value(ok('${HostShellPathResolver.marker}/c/bin'));
        },
      );
      final second = await HostShellPathResolver.resolve(
        posixPlatformOverride: true,
        runner: (executable, arguments, {stdoutEncoding, stderrEncoding}) {
          calls++;
          return Future.value(ok('${HostShellPathResolver.marker}/other'));
        },
      );
      expect(second, '/c/bin');
      expect(calls, 1);
      expect(HostShellPathResolver.cachedPath, '/c/bin');
    });

    test('caches failure as null without retrying', () async {
      // Deterministic candidates: ['zsh', 'bash'] regardless of host SHELL.
      HostShellPathResolver.debugShellOverride = () => '/bin/zsh';
      var calls = 0;
      final result = await HostShellPathResolver.resolve(
        posixPlatformOverride: true,
        runner: (executable, arguments, {stdoutEncoding, stderrEncoding}) {
          calls++;
          return Future.value(ok('garbage without marker'));
        },
      );
      expect(result, isNull);
      expect(calls, 2); // zsh + bash both probed
      final again = await HostShellPathResolver.resolve(
        posixPlatformOverride: true,
        runner: (executable, arguments, {stdoutEncoding, stderrEncoding}) {
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
        runner: (executable, arguments, {stdoutEncoding, stderrEncoding}) =>
            fail('must not spawn'),
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
