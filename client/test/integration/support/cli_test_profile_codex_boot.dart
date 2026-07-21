import 'package:teampilot/services/terminal/terminal_session.dart';

/// Codex fullscreen composer prefix (`›` U+203A).
const kCodexComposerPrefix = '\u203a';

/// Dismisses Codex first-run / trust / sign-in gates via Enter.
///
/// Session launch already provisions `auth.json` + trust under CODEX_HOME; this
/// is a safety net when a gate still paints (mirrors codex_deliver IT).
Future<void> dismissCodexBootGates(TerminalSession session) async {
  await session.probe.syncDisplayGrid();
  final frame = session.probe.describeProbeWindow(scanRows: 52);
  if (_codexGateNeedsEnter(frame)) {
    session.input.writeToPty('\r');
  }
}

/// Waits until Codex's status footer (`… default · …`) is visible — that only
/// paints after landing/trust screens clear — and the shell is not working.
Future<bool> bootCodexToPrompt(TerminalSession session) async {
  final deadline = DateTime.now().add(const Duration(seconds: 90));
  var lastNudge = DateTime.fromMillisecondsSinceEpoch(0);

  while (DateTime.now().isBefore(deadline)) {
    if (!session.isRunning && !session.isConnecting) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      continue;
    }

    await session.probe.syncDisplayGrid();
    final frame = session.probe.describeProbeWindow(scanRows: 52);

    if (_codexGateNeedsEnter(frame) &&
        DateTime.now().difference(lastNudge).inMilliseconds > 600) {
      session.input.writeToPty('\r');
      lastNudge = DateTime.now();
    }

    // Status footer is more reliable than the `›` composer glyph alone: the
    // sign-in landing also paints content, but only the ready TUI shows
    // `<model> default · <cwd>`.
    final atPrompt = frame.contains('default \u00b7') ||
        frame.contains(kCodexComposerPrefix);
    final settled = !session.activityTracker.isWorking;
    if (atPrompt && settled) {
      return true;
    }

    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
  return false;
}

bool _codexGateNeedsEnter(String frame) {
  return frame.contains('Press enter') ||
      frame.contains('trust') ||
      frame.contains('Yes, continue') ||
      frame.contains('Sign in with ChatGPT');
}
