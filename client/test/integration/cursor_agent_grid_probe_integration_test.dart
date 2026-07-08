@Tags(['integration', 'linux-pty'])
@Timeout(Duration(minutes: 2))
library;

/// Diagnostic probe: does cursor-agent's TUI echo bracketed-paste input back
/// into PTY output (visible on the alacritty mirror grid)?
///
/// Answers why landing delivery hits `pasteNotFound` on cursor:
/// - needle found  → grid ACK works; miss was timing/CLI-resolution, so cursor
///   can use the same grid-probe path as claude.
/// - needle absent → cursor stages input without echoing to PTY output; grid
///   ACK cannot work and timed paste+CR is required (usesGridPasteAck=false).
///
/// Run:
///   LD_LIBRARY_PATH=build/linux/x64/debug/bundle/lib \
///     flutter test test/integration/cursor_agent_grid_probe_integration_test.dart \
///     --tags "integration && linux-pty"

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/terminal/fullscreen_input_screen_probe.dart';
import 'package:teampilot/services/terminal/pty_automation_needle.dart';
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

Future<FullscreenPromptAnchor?> _pollNeedle(
  TerminalSession session,
  String needle, {
  int scanRows = 24,
  Duration timeout = const Duration(seconds: 6),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    await session.probe.syncDisplayGrid();
    final anchor = session.probe.locateFullscreenPromptNeedle(
      needle,
      scanRows: scanRows,
    );
    if (anchor != null) return anchor;
    await Future<void>.delayed(const Duration(milliseconds: 150));
  }
  return null;
}

Future<bool> _waitUntilPresent(
  TerminalSession session,
  String marker, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    await session.probe.syncDisplayGrid();
    if (session.probe.describeProbeWindow(scanRows: 24).contains(marker)) {
      return true;
    }
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
  return false;
}

/// Waits until the TUI paints something in the bottom rows (boot frame ready).
Future<bool> _waitForTuiPaint(
  TerminalSession session, {
  Duration timeout = const Duration(seconds: 15),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    await session.probe.syncDisplayGrid();
    if (session.probe.hasInputBoxContent(scanRows: 24)) return true;
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
  return false;
}

void main() {
  group('cursor-agent grid probe (real PTY + alacritty mirror)', () {
    test('bracketed paste visibility on the mirror grid', () async {
      IntegrationPrerequisites.skipUnlessNativePty();
      final cursorAgent = _resolveCursorAgentPath();
      if (cursorAgent == null) {
        markTestSkipped('cursor-agent not on PATH');
        return;
      }

      // Real HOME: the probe needs the logged-in TUI (isolated HOME lands on
      // the login screen, which has no input box to paste into).
      final tmpWork = await Directory.systemTemp.createTemp('cursor_probe_work_');
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
      );
      addTearDown(session.dispose);

      final painted = await _waitForTuiPaint(session);
      // ignore: avoid_print
      print('--- cursor-agent boot frame (painted=$painted) ---\n'
          '${session.probe.describeProbeWindow(scanRows: 24)}');
      if (!painted) {
        fail('cursor-agent TUI never painted anything\n'
            '${session.probe.describeProbeWindow(scanRows: 24)}');
      }

      // Fresh workspace shows a trust dialog before the input box.
      if (session
          .describeProbeWindow(scanRows: 24)
          .contains('Trust this workspace')) {
        session.input.writeToPty('a');
      }
      // Trust residue stays on screen; wait for the input prompt row instead.
      final promptReady = await _waitUntilPresent(
        session,
        '→',
        timeout: const Duration(seconds: 20),
      );
      if (!promptReady) {
        fail('input prompt (→) never appeared\n'
            '${session.probe.describeProbeWindow(scanRows: 24)}');
      }

      // Give the TUI extra settle after first paint (auth prompt / input box).
      await Future<void>.delayed(const Duration(seconds: 3));
      await session.probe.syncDisplayGrid();
      // ignore: avoid_print
      print('--- pre-paste frame ---\n'
          '${session.probe.describeProbeWindow(scanRows: 24)}');

      const needle = 'grid-probe-hello-42';
      await session.input.pasteText(needle);

      final anchor = await _pollNeedle(session, needle);
      // ignore: avoid_print
      print('--- after paste (anchor=$anchor) ---\n'
          '${session.probe.describeProbeWindow(scanRows: 24)}');

      // No CR on purpose: submitting would start a real agent turn on the
      // user's cursor account. Paste visibility alone answers the grid-ACK
      // question (pasteNotFound happens before any CR).
      expect(
        anchor,
        isNotNull,
        reason:
            'pasted text should be visible on the mirror grid if cursor-agent '
            'echoes staged input to PTY output. Bottom rows:\n'
            '${session.probe.describeProbeWindow(scanRows: 24)}',
      );

      // Production-shaped case: doorbell-style long text (needle = 40-char
      // prefix) with the same clear→paste sequence deliverPasteAndSubmit uses.
      await session.input.clearStagedInput();
      await Future<void>.delayed(const Duration(milliseconds: 200));
      const doorbell =
          '[teammate-bus] you have 1 unread message from user (operator) — '
          'call read_messages to fetch it, then continue your idle loop';
      final doorbellNeedle = PtyAutomationNeedle.forText(doorbell);
      await session.input.pasteText(doorbell);
      final doorbellAnchor = await _pollNeedle(session, doorbellNeedle);
      // ignore: avoid_print
      print('--- after doorbell paste (anchor=$doorbellAnchor, '
          'needle="$doorbellNeedle") ---\n'
          '${session.probe.describeProbeWindow(scanRows: 24)}');
      expect(
        doorbellAnchor,
        isNotNull,
        reason: 'doorbell needle should be locatable even when the long text '
            'wraps inside the cursor input box',
      );
    });
  });
}
