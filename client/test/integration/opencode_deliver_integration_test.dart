@Tags(['integration', 'linux-pty'])
@Timeout(Duration(minutes: 3))
library;

/// Production-shaped opencode PTY delivery with [FullscreenCrAckStrategy.anchorCellClears].
///
/// opencode is not yet `usesFullScreenInput` in production (still `writeln`), but
/// this test exercises the same [FullscreenPtyAutomation] path we will use once
/// full-screen doorbell inject is enabled.
///
/// Run:
///   LD_LIBRARY_PATH=build/linux/x64/debug/bundle/lib \
///     flutter test test/integration/opencode_deliver_integration_test.dart \
///     --tags "integration && linux-pty"

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/terminal/fullscreen_cr_ack_config.dart';
import 'package:teampilot/services/terminal/fullscreen_pty_automation.dart';
import 'package:teampilot/services/terminal/terminal_fullscreen_pty_port.dart';
import 'package:teampilot/services/terminal/terminal_session.dart';

import 'support/integration_prerequisites.dart';
import 'support/local_pty_probe_harness.dart';

String? _resolveOpencodePath() {
  try {
    final result = Process.runSync('which', ['opencode']);
    if (result.exitCode != 0) return null;
    final line = result.stdout.toString().trim().split('\n').first.trim();
    return line.isEmpty ? null : line;
  } on ProcessException {
    return null;
  }
}

/// Dismisses blocking modals (version update) so paste lands on the composer.
Future<void> _dismissOpencodeModals(
  TerminalSession session, {
  required int scanRows,
  Duration timeout = const Duration(seconds: 8),
}) async {
  final deadline = DateTime.now().add(timeout);
  var lastEsc = DateTime(0);
  while (DateTime.now().isBefore(deadline)) {
    await session.syncDisplayGrid();
    final frame = session.describeProbeWindow(scanRows: scanRows);
    if (!frame.contains('Update Available')) return;
    final now = DateTime.now();
    if (now.difference(lastEsc).inMilliseconds > 400) {
      session.writeToPty('\x1b');
      lastEsc = now;
    }
    await Future<void>.delayed(const Duration(milliseconds: 150));
  }
  // Fallback: select "Skip" on the update modal.
  session.writeToPty('\x1b[D\r');
  await Future<void>.delayed(const Duration(milliseconds: 300));
}

/// Boots the opencode TUI and waits until the composer input is ready.
Future<void> _bootOpencodePrompt(
  TerminalSession session, {
  required int scanRows,
}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 45));
  var stableReads = 0;
  while (DateTime.now().isBefore(deadline)) {
    await session.syncDisplayGrid();
    final frame = session.describeProbeWindow(scanRows: scanRows);

    if (frame.contains('Update Available')) {
      await _dismissOpencodeModals(session, scanRows: scanRows);
      stableReads = 0;
      continue;
    }

    if (frame.contains('Ask anything')) {
      stableReads++;
      if (stableReads >= 3) {
        await Future<void>.delayed(const Duration(seconds: 1));
        await _dismissOpencodeModals(session, scanRows: scanRows);
        return;
      }
    } else {
      stableReads = 0;
    }

    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
  fail('opencode composer never appeared\n'
      '${session.describeProbeWindow(scanRows: scanRows)}');
}

void main() {
  group('opencode deliver (real PTY + production automation)', () {
    for (final viewport in const [(cols: 80, rows: 24), (cols: 80, rows: 52)]) {
      test(
        'deliverPasteAndSubmit at ${viewport.cols}x${viewport.rows}',
        () async {
          IntegrationPrerequisites.skipUnlessNativePty();
          final opencode = _resolveOpencodePath();
          if (opencode == null) {
            markTestSkipped('opencode not on PATH');
            return;
          }

          // Real HOME/config: isolated dirs land on onboarding modals and
          // provider pickers that block the composer (see grid probe notes).
          final tmpWork =
              await Directory.systemTemp.createTemp('opencode_deliver_work_');
          addTearDown(() async {
            try {
              await tmpWork.delete(recursive: true);
            } catch (_) {}
          });

          final session = await LocalPtyProbeHarness.connectShell(
            executable: opencode,
            arguments: const [],
            confirmFallback: const Duration(seconds: 3),
            workingDirectory: tmpWork.path,
            viewportColumns: viewport.cols,
            viewportRows: viewport.rows,
            extraEnvironment: {
              ...Platform.environment,
              'TERM': 'xterm-256color',
            },
          );
          addTearDown(session.dispose);

          await _bootOpencodePrompt(session, scanRows: viewport.rows);
          await _dismissOpencodeModals(session, scanRows: viewport.rows);
          await session.syncDisplayGrid();

          final text = 'opencode-probe-${DateTime.now().millisecondsSinceEpoch}';

          // Pre-paste so deliverPasteAndSubmit skips clearStagedInput (Ctrl-U).
          // On a 24-row viewport that keystroke races opencode's async update
          // modal and paste probes miss the needle.
          await session.pasteText(text);
          await Future<void>.delayed(const Duration(milliseconds: 500));
          await _dismissOpencodeModals(session, scanRows: viewport.rows);
          await session.syncDisplayGrid();

          final automation = FullscreenPtyAutomation();
          final port = TerminalFullscreenPtyPort(
            session,
            aborted: () => false,
            crAckConfig: const FullscreenCrAckConfig(
              strategy: FullscreenCrAckStrategy.anchorCellClears,
            ),
          );

          final grid = session.engine.grid;
          // ignore: avoid_print
          print('--- pre-deliver ${viewport.cols}x${viewport.rows} '
              'grid=${grid.columns}x${grid.rows} ---\n'
              '${session.describeProbeWindow(scanRows: viewport.rows)}');

          final outcome = await automation.deliverPasteAndSubmit(
            port: port,
            text: text,
            pasteSettle: const Duration(milliseconds: 500),
          );

          await session.syncDisplayGrid();
          final afterDeliver = session.describeProbeWindow(scanRows: viewport.rows);
          // ignore: avoid_print
          print('--- deliver outcome=$outcome ---\n$afterDeliver');

          expect(
            outcome,
            FullscreenPtyDeliveryOutcome.submitted,
            reason: 'opencode anchorCellClears ACK must pass at '
                '${viewport.cols}x${viewport.rows}. Dump:\n$afterDeliver',
          );
        },
      );
    }
  });
}
