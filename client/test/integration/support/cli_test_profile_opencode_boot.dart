import 'package:teampilot/services/terminal/terminal_session.dart';

/// OpenCode fullscreen composer prefix (`┃` U+2503).
const kOpencodeComposerPrefix = '\u2503';

/// Placeholder text on the idle OpenCode composer.
const kOpencodeComposerHint = 'Ask anything';

/// Dismisses blocking OpenCode modals (version update / exhausted-script
/// retries) so paste lands on the composer.
Future<void> dismissOpencodeBootGates(TerminalSession session) async {
  final deadline = DateTime.now().add(const Duration(seconds: 8));
  var lastEsc = DateTime.fromMillisecondsSinceEpoch(0);
  while (DateTime.now().isBefore(deadline)) {
    await session.probe.syncDisplayGrid();
    final frame = session.probe.describeProbeWindow(scanRows: 52);
    final needsEsc = frame.contains('Update Available') ||
        frame.contains('scenario exhausted') ||
        frame.contains('Internal Server Error') ||
        frame.contains('retryin');
    if (!needsEsc) return;
    final now = DateTime.now();
    if (now.difference(lastEsc).inMilliseconds > 400) {
      session.input.writeToPty('\x1b');
      lastEsc = now;
    }
    await Future<void>.delayed(const Duration(milliseconds: 150));
  }
  // Fallback: select "Skip" on the update modal.
  session.input.writeToPty('\x1b[D\r');
  await Future<void>.delayed(const Duration(milliseconds: 300));
}

/// Waits until OpenCode's composer (`Ask anything` / `┃`) is stable.
Future<bool> bootOpencodeToPrompt(TerminalSession session) async {
  final deadline = DateTime.now().add(const Duration(seconds: 90));
  var stableReads = 0;
  var lastEsc = DateTime.fromMillisecondsSinceEpoch(0);

  while (DateTime.now().isBefore(deadline)) {
    if (!session.isRunning && !session.isConnecting) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      continue;
    }

    await session.probe.syncDisplayGrid();
    final frame = session.probe.describeProbeWindow(scanRows: 52);

    if (frame.contains('Update Available')) {
      await dismissOpencodeBootGates(session);
      stableReads = 0;
      continue;
    }

    final atComposer = frame.contains(kOpencodeComposerHint) ||
        frame.contains(kOpencodeComposerPrefix);
    final settled = !session.activityTracker.isWorking;
    final errorRetry = frame.contains('scenario exhausted') ||
        frame.contains('Internal Server Error');
    if (errorRetry &&
        DateTime.now().difference(lastEsc).inMilliseconds > 600) {
      session.input.writeToPty('\x1b');
      lastEsc = DateTime.now();
      stableReads = 0;
      continue;
    }
    if (atComposer && settled) {
      stableReads++;
      if (stableReads >= 3) {
        // Brief settle so async update modals do not race the first paste.
        await Future<void>.delayed(const Duration(seconds: 1));
        await dismissOpencodeBootGates(session);
        return true;
      }
    } else {
      stableReads = 0;
    }

    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
  return false;
}
