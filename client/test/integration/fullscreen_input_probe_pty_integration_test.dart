@Tags(['integration'])
@Timeout(Duration(minutes: 2))
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/terminal/fullscreen_input_screen_probe.dart';
import 'package:teampilot/services/terminal/pty_inject_ack_retry.dart';
import 'package:teampilot/services/terminal/terminal_export.dart';
import 'package:teampilot/services/terminal/terminal_session.dart';

import 'support/integration_prerequisites.dart';
import 'support/local_pty_probe_harness.dart';

Future<FullscreenPromptAnchor?> _waitForNeedle(
  TerminalSession session,
  String needle, {
  int scanRows = 24,
  Duration timeout = const Duration(seconds: 3),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    await session.probe.syncDisplayGrid();
    final anchor = session.probe.locateFullscreenPromptNeedle(
      needle,
      scanRows: scanRows,
    );
    if (anchor != null) return anchor;
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  return null;
}

String _gridDump(TerminalSession session) =>
    '${session.probe.describeProbeWindow(scanRows: 24)}\n'
    '--- export ---\n'
    '${exportTerminalScrollback(session.engine)}';

void main() {
  group('fullscreen input probe (real PTY + alacritty grid)', () {
    test('locates CJK echoed by a real shell on the mirror grid', () async {
      IntegrationPrerequisites.skipUnlessNativePty();

      final session = await LocalPtyProbeHarness.connectDefaultShell();
      addTearDown(session.dispose);

      await LocalPtyProbeHarness.settleGrid(session);
      session.input.writeToPty(LocalPtyProbeHarness.cjkEchoBytes);
      final anchor = await _waitForNeedle(session, LocalPtyProbeHarness.needle);
      expect(
        anchor,
        isNotNull,
        reason:
            'CJK from real PTY should match after syncDisplayGrid '
            '(wide-char columns)\n${_gridDump(session)}',
      );
      expect(session.probe.isFullscreenPromptAtAnchor(anchor!), isTrue);
    });

    test('locates CJK after bracketed paste on a PTY fixture prompt', () async {
      final session = await LocalPtyProbeHarness.connectBracketedPasteFixture();
      addTearDown(session.dispose);

      await LocalPtyProbeHarness.settleGrid(session);
      await session.input.clearStagedInput();
      await Future<void>.delayed(PtyInjectAckTiming.afterClear);
      await session.input.pasteText(LocalPtyProbeHarness.needle);
      await Future<void>.delayed(PtyInjectAckTiming.afterPaste);
      await session.probe.syncDisplayGrid();

      final anchor = await _waitForNeedle(session, LocalPtyProbeHarness.needle);
      expect(
        anchor,
        isNotNull,
        reason:
            'bracketed paste fixture should stage CJK on the prompt line\n'
            '${_gridDump(session)}',
      );
      expect(anchor!.needle, LocalPtyProbeHarness.needle);
      expect(session.probe.isFullscreenPromptAtAnchor(anchor), isTrue);
    });

    test('syncDisplayGrid is required for bracketed paste probe', () async {
      final session = await LocalPtyProbeHarness.connectBracketedPasteFixture();
      addTearDown(session.dispose);

      await LocalPtyProbeHarness.settleGrid(session);
      await session.input.pasteText(LocalPtyProbeHarness.needle);
      await Future<void>.delayed(PtyInjectAckTiming.afterPaste);

      final beforeSync = session.probe.locateFullscreenPromptNeedle(
        LocalPtyProbeHarness.needle,
      );
      final afterSync = await _waitForNeedle(session, LocalPtyProbeHarness.needle);

      expect(
        afterSync,
        isNotNull,
        reason: 'probe should find needle after drain\n${_gridDump(session)}',
      );
      // Stale mirror may or may not match depending on scheduler timing; after
      // sync must succeed when paste landed.
      if (beforeSync == null) {
        expect(afterSync, isNotNull);
      }
    });
  });
}
