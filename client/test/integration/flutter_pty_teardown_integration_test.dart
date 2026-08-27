@Tags(['integration', 'linux-pty'])
import 'dart:io';

import 'package:flutter_pty_new/flutter_pty_new.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/integration_prerequisites.dart';

/// Regression tests for native resource teardown of [Pty].
///
/// Each created PTY used to permanently leak its master fd, the parent-side
/// slave fd, and a read thread blocked forever on `read()` — because nothing
/// ever closed the master and the slave was never closed after fork.
/// See client/packages/flutter_pty_new/src/forkpty.c.
void main() {
  int countOpenFds() => Directory('/proc/self/fd').listSync().length;
  int countThreads() => Directory('/proc/self/task').listSync().length;

  Future<Pty> startExitingShell() async {
    final pty = Pty.start('/bin/sh', arguments: const ['-c', 'exit 0']);
    await pty.exitCode;
    return pty;
  }

  test('disposing an exited PTY releases its fds and read thread', () async {
    IntegrationPrerequisites.skipUnlessNativePty();
    if (!Platform.isLinux) {
      markTestSkipped('Assertions count /proc fds and threads (Linux only).');
    }

    // Warm-up: load the dylib and settle one-time process-wide allocations
    // before taking the baselines.
    final warmup = await startExitingShell();
    warmup.kill();
    warmup.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final fdsBefore = countOpenFds();
    final threadsBefore = countThreads();

    const rounds = 4;
    for (var i = 0; i < rounds; i++) {
      final pty = await startExitingShell();
      pty.kill();
      pty.dispose();
    }
    // Allow read threads to observe closure (poll tick) and exit.
    await Future<void>.delayed(const Duration(milliseconds: 800));

    expect(
      countOpenFds() - fdsBefore,
      lessThanOrEqualTo(1),
      reason: 'each disposed PTY must not keep its master/slave fds open',
    );
    expect(
      countThreads() - threadsBefore,
      lessThanOrEqualTo(1),
      reason: 'each disposed PTY must not leak a blocked read thread',
    );
  });

  test('creating a PTY does not leak the parent-side slave fd', () async {
    IntegrationPrerequisites.skipUnlessNativePty();
    if (!Platform.isLinux) {
      markTestSkipped('Assertions count /proc fds and threads (Linux only).');
    }

    final warmup = await startExitingShell();
    warmup.kill();
    warmup.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final fdsBefore = countOpenFds();

    const rounds = 4;
    final ptys = <Pty>[];
    for (var i = 0; i < rounds; i++) {
      ptys.add(await startExitingShell());
    }
    // The children exited; each live Pty owns one master and a two-fd reader
    // wake pipe, but never an extra parent-side slave copy.
    final growthAfterCreateOnly = countOpenFds() - fdsBefore;
    for (final pty in ptys) {
      pty.kill();
      pty.dispose();
    }
    await Future<void>.delayed(const Duration(milliseconds: 800));

    expect(
      growthAfterCreateOnly,
      lessThanOrEqualTo(rounds * 3),
      reason:
          'creating N PTYs should open at most three fds per PTY '
          '(master plus the reader wake pipe; no parent-side slave)',
    );
    expect(
      countOpenFds() - fdsBefore,
      lessThanOrEqualTo(1),
      reason: 'after dispose all PTY fds must be released',
    );
  });

  test('disposing an ack-blocked PTY does not deadlock', () async {
    IntegrationPrerequisites.skipUnlessNativePty();
    if (!Platform.isLinux) {
      markTestSkipped(
        'Assertions exercise the Linux native PTY implementation.',
      );
    }

    final pty = Pty.start(
      '/bin/sh',
      arguments: const ['-c', 'printf ready; exec sleep 30'],
      ackRead: true,
    );
    await pty.output.first.timeout(const Duration(seconds: 5));

    // The reader is waiting for ackRead here. close must wake that wait before
    // joining the reader thread, otherwise this call would block forever.
    pty.kill(ProcessSignal.sigkill);
    pty.dispose();
    await pty.exitCode.timeout(const Duration(seconds: 5));
  });
}
