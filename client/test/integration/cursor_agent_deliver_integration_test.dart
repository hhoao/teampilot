@Tags(['integration', 'linux-pty'])
@Timeout(Duration(minutes: 3))
library;

/// Production-shaped cursor-agent PTY delivery: clear → paste → grid ACK → CR.
///
/// Reproduces landing `pasteNotFound` with a tall viewport (52 rows, like the
/// embedded terminal) and the real [FullscreenPtyAutomation] path.
///
/// Run:
///   LD_LIBRARY_PATH=build/linux/x64/debug/bundle/lib \
///     flutter test test/integration/cursor_agent_deliver_integration_test.dart \
///     --tags "integration && linux-pty"

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/cli/cursor/capabilities/terminal_behavior.dart';
import 'package:teampilot/services/terminal/fullscreen_cr_ack_config.dart';
import 'package:teampilot/services/terminal/fullscreen_pty_automation.dart';
import 'package:teampilot/services/terminal/terminal_fullscreen_pty_port.dart';
import 'package:teampilot/services/terminal/terminal_session.dart';

import 'support/integration_prerequisites.dart';
import 'support/local_pty_probe_harness.dart';

String? _resolveCursorAgentPath() {
  try {
    final result = Process.runSync('which', ['cursor-agent']);
    if (result.exitCode != 0) return null;
    final line = result.stdout.toString().trim().split('\n').first.trim();
    return line.isEmpty ? null : line;
  } on ProcessException {
    return null;
  }
}

Future<bool> _waitUntilPresent(
  TerminalSession session,
  String marker, {
  int scanRows = 24,
  Duration timeout = const Duration(seconds: 20),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    await session.probe.syncDisplayGrid();
    if (session.probe.describeProbeWindow(scanRows: scanRows).contains(marker)) {
      return true;
    }
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
  return false;
}

Future<void> _bootCursorPrompt(
  TerminalSession session, {
  required int scanRows,
}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 20));
  while (DateTime.now().isBefore(deadline)) {
    await session.probe.syncDisplayGrid();
    if (session.probe.hasInputBoxContent(scanRows: scanRows)) break;
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }

  if (session.probe.describeProbeWindow(scanRows: scanRows).contains('Trust')) {
    session.input.writeToPty('a');
  }
  final promptReady = await _waitUntilPresent(session, '→', scanRows: scanRows);
  if (!promptReady) {
    fail('input prompt never appeared\n'
        '${session.probe.describeProbeWindow(scanRows: scanRows)}');
  }
  await Future<void>.delayed(const Duration(seconds: 2));
  await session.probe.syncDisplayGrid();
}

void main() {
  group('cursor-agent deliver (real PTY + production automation)', () {
    for (final viewport in const [(cols: 80, rows: 24), (cols: 80, rows: 52)]) {
      test(
        'deliverPasteAndSubmit hello at ${viewport.cols}x${viewport.rows}',
        () async {
          IntegrationPrerequisites.skipUnlessNativePty();
          final cursorAgent = _resolveCursorAgentPath();
          if (cursorAgent == null) {
            markTestSkipped('cursor-agent not on PATH');
            return;
          }

          final tmpWork =
              await Directory.systemTemp.createTemp('cursor_deliver_work_');
          addTearDown(() async {
            try {
              await tmpWork.delete(recursive: true);
            } catch (_) {}
          });

          final session = await LocalPtyProbeHarness.connectShell(
            executable: cursorAgent,
            arguments: ['--workspace', tmpWork.path],
            confirmFallback: const Duration(seconds: 3),
            workingDirectory: tmpWork.path,
            viewportColumns: viewport.cols,
            viewportRows: viewport.rows,
          );
          addTearDown(session.dispose);

          const scanRows = 24;
          await _bootCursorPrompt(session, scanRows: viewport.rows);

          await session.probe.syncDisplayGrid();
          final grid = session.engine.grid;
          // ignore: avoid_print
          print('--- pre-deliver ${viewport.cols}x${viewport.rows} '
              'grid=${grid.columns}x${grid.rows} ---\n'
              '${session.probe.describeProbeWindow(scanRows: viewport.rows)}');

          const text = 'hello';
          final automation = FullscreenPtyAutomation();
          final port = TerminalFullscreenPtyPort(
            input: session.input,
            probe: session.probe,
            aborted: () => false,
            painted: session.observationPainted,
          );
          final outcome = await automation.deliverPasteAndSubmit(
            port: port,
            text: text,
            pasteSettle: const Duration(milliseconds: 150),
          );

          await session.probe.syncDisplayGrid();
          // ignore: avoid_print
          print('--- deliver outcome=$outcome ---\n'
              '${session.probe.describeProbeWindow(scanRows: viewport.rows)}');

          expect(
            outcome,
            FullscreenPtyDeliveryOutcome.submitted,
            reason:
                'production deliverPasteAndSubmit should paste, grid-ACK, and '
                'CR-submit at ${viewport.cols}x${viewport.rows}. '
                'Grid dump:\n${session.probe.describeProbeWindow(scanRows: viewport.rows)}',
          );
        },
      );
    }

    test('deliverPasteAndSubmit short A twice at 80x52', () async {
      IntegrationPrerequisites.skipUnlessNativePty();
      final cursorAgent = _resolveCursorAgentPath();
      if (cursorAgent == null) {
        markTestSkipped('cursor-agent not on PATH');
        return;
      }

      final tmpWork =
          await Directory.systemTemp.createTemp('cursor_deliver_short_');
      addTearDown(() async {
        try {
          await tmpWork.delete(recursive: true);
        } catch (_) {}
      });

      const cols = 80;
      const rows = 52;
      final session = await LocalPtyProbeHarness.connectShell(
        executable: cursorAgent,
        arguments: ['--workspace', tmpWork.path],
        confirmFallback: const Duration(seconds: 3),
        workingDirectory: tmpWork.path,
        viewportColumns: cols,
        viewportRows: rows,
      );
      addTearDown(session.dispose);

      await _bootCursorPrompt(session, scanRows: rows);

      final automation = FullscreenPtyAutomation();
      final port = TerminalFullscreenPtyPort(
        input: session.input,
        probe: session.probe,
        aborted: () => false,
        painted: session.observationPainted,
        crAckConfig: FullscreenCrAckConfig(
          strategy: const CursorTerminalBehavior().fullscreenCrAckStrategy,
          composerPrefix:
              const CursorTerminalBehavior().fullscreenComposerPrefix,
        ),
      );

      for (var i = 0; i < 2; i++) {
        final outcome = await automation.deliverPasteAndSubmit(
          port: port,
          text: 'A',
          pasteSettle: const Duration(milliseconds: 150),
        );
        await session.probe.syncDisplayGrid();
        // ignore: avoid_print
        print('--- short A deliver #$i outcome=$outcome ---\n'
            '${session.probe.describeProbeWindow(scanRows: rows)}');
        expect(
          outcome,
          FullscreenPtyDeliveryOutcome.submitted,
          reason:
              'short needle deliver #$i must submit without hanging/crStuck. '
              'Grid:\n${session.probe.describeProbeWindow(scanRows: rows)}',
        );
        // Let Cursor paint a fresh empty composer before the next paste.
        await Future<void>.delayed(const Duration(seconds: 2));
        await session.probe.syncDisplayGrid();
      }
    });
  });
}
