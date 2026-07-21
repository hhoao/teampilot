import 'package:teampilot/services/terminal/terminal_session.dart';

/// Claude Code fullscreen composer prefix (`❯`).
const kClaudeComposerPrefix = '\u276f';

/// Dismisses Claude first-run / trust / custom-API-key gates via Enter.
///
/// Product launch already seeds `hasTrustDialogAccepted` and
/// `customApiKeyResponses`, so this is a safety net when a gate still paints.
Future<void> dismissClaudeBootGates(TerminalSession session) async {
  await session.probe.syncDisplayGrid();
  final frame = session.probe.describeProbeWindow(scanRows: 52);
  if (_claudeGateNeedsEnter(frame)) {
    session.input.writeToPty('\r');
  }
}

/// Waits until Claude's composer (`❯`) is visible and the shell is not working.
Future<bool> bootClaudeToPrompt(TerminalSession session) async {
  final deadline = DateTime.now().add(const Duration(seconds: 90));
  var lastNudge = DateTime.fromMillisecondsSinceEpoch(0);

  while (DateTime.now().isBefore(deadline)) {
    if (!session.isRunning && !session.isConnecting) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      continue;
    }

    await session.probe.syncDisplayGrid();
    final frame = session.probe.describeProbeWindow(scanRows: 52);

    if (_claudeGateNeedsEnter(frame) &&
        DateTime.now().difference(lastNudge).inMilliseconds > 600) {
      session.input.writeToPty('\r');
      lastNudge = DateTime.now();
    }

    final atComposer = frame.contains(kClaudeComposerPrefix);
    final settled = !session.activityTracker.isWorking;
    if (atComposer && settled) {
      return true;
    }

    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
  return false;
}

bool _claudeGateNeedsEnter(String frame) {
  final lower = frame.toLowerCase();
  return lower.contains('press enter') ||
      lower.contains('trust this') ||
      lower.contains('yes, continue') ||
      lower.contains('custom api key') ||
      lower.contains('detected a custom') ||
      lower.contains('do you want to use');
}
