@Tags(['integration', 'linux-pty'])
@Timeout(Duration(minutes: 3))
library;

/// Production-shaped codex PTY delivery: clear → paste → grid ACK → CR.
///
/// Mirrors the cursor-agent deliver test: boot the real codex TUI on a live PTY
/// at both a 24-row and a tall 52-row viewport (like the embedded terminal),
/// then run the real [FullscreenPtyAutomation] path with codex's
/// region-moved-down ACK rule ([CodexTerminalBehavior.composerRegion]).
///
/// Run:
///   LD_LIBRARY_PATH=build/linux/x64/debug/bundle/lib \
///     flutter test test/integration/codex_deliver_integration_test.dart \
///     --tags "integration && linux-pty"

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/cli/codex/capabilities/terminal_behavior.dart';
import 'package:teampilot/services/terminal/fullscreen_pty_automation.dart';
import 'package:teampilot/services/terminal/terminal_fullscreen_pty_port.dart';
import 'package:teampilot/services/terminal/terminal_session.dart';

import 'support/integration_prerequisites.dart';
import 'support/local_pty_probe_harness.dart';

String? _resolveCodexPath() {
  try {
    final result = Process.runSync('which', ['codex']);
    if (result.exitCode != 0) return null;
    final line = result.stdout.toString().trim().split('\n').first.trim();
    return line.isEmpty ? null : line;
  } on ProcessException {
    return null;
  }
}

/// Boots the codex TUI, dismissing first-run screens (sign-in landing, trust /
/// approval prompts, "Press enter to continue"), then waits for the composer
/// input box — matched by codex's `▌`/`Ask Codex`/`send` prompt row rather than
/// any painted content (the sign-in landing also paints).
Future<void> _bootCodexPrompt(
  TerminalSession session, {
  required int scanRows,
}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 30));
  var lastNudge = DateTime(0);
  while (DateTime.now().isBefore(deadline)) {
    await session.probe.syncDisplayGrid();
    final frame = session.probe.describeProbeWindow(scanRows: scanRows);

    // Composer ready: codex paints the model/cwd status footer
    // (`<model> default · <cwd>`) only after every landing/trust screen clears.
    if (frame.contains('default \u00b7')) {
      return;
    }

    // Dismiss first-run screens: sign-in landing, "trust this directory",
    // "Press enter to continue". Each is confirmed with Enter (default option
    // is "Yes, continue").
    final now = DateTime.now();
    final needsEnter = frame.contains('Press enter') ||
        frame.contains('trust') ||
        frame.contains('Yes, continue') ||
        frame.contains('Sign in with ChatGPT');
    if (needsEnter && now.difference(lastNudge).inMilliseconds > 600) {
      session.input.writeToPty('\r');
      lastNudge = now;
    }
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
  fail('codex composer never appeared\n'
      '${session.probe.describeProbeWindow(scanRows: scanRows)}');
}

void main() {
  group('codex deliver (real PTY + production automation)', () {
    for (final viewport in const [(cols: 80, rows: 24), (cols: 80, rows: 52)]) {
      test(
        'deliverPasteAndSubmit hello at ${viewport.cols}x${viewport.rows}',
        () async {
          IntegrationPrerequisites.skipUnlessNativePty();
          final codex = _resolveCodexPath();
          if (codex == null) {
            markTestSkipped('codex not on PATH');
            return;
          }

          // Isolated CODEX_HOME under the real HOME (codex refuses helper
          // aliases under /tmp) so the test never touches real codex config.
          final realHome = Platform.environment['HOME'] ?? '/tmp';
          final tmpHome = await Directory(realHome)
              .createTemp('.codex_deliver_home_');
          final tmpWork =
              await Directory.systemTemp.createTemp('codex_deliver_work_');
          addTearDown(() async {
            try {
              await tmpHome.delete(recursive: true);
              await tmpWork.delete(recursive: true);
            } catch (_) {}
          });

          // Copy real auth into the isolated home so codex boots straight to the
          // composer instead of the sign-in landing (no real config is mutated).
          final realAuth = File('$realHome/.codex/auth.json');
          if (!realAuth.existsSync()) {
            markTestSkipped('~/.codex/auth.json not found — codex not signed in');
            return;
          }
          await realAuth.copy('${tmpHome.path}/auth.json');

          final session = await LocalPtyProbeHarness.connectShell(
            executable: codex,
            arguments: [
              '--cd',
              tmpWork.path,
              '--dangerously-bypass-approvals-and-sandbox',
            ],
            confirmFallback: const Duration(seconds: 3),
            workingDirectory: tmpWork.path,
            viewportColumns: viewport.cols,
            viewportRows: viewport.rows,
            extraEnvironment: {
              ...Platform.environment,
              'CODEX_HOME': tmpHome.path,
              // Flutter's test runner sets TERM=dumb; codex refuses its TUI.
              'TERM': 'xterm-256color',
            },
          );
          addTearDown(session.dispose);

          await _bootCodexPrompt(session, scanRows: viewport.rows);
          await Future<void>.delayed(const Duration(seconds: 1));
          await session.probe.syncDisplayGrid();

          final grid = session.engine.grid;
          // ignore: avoid_print
          print('--- pre-deliver ${viewport.cols}x${viewport.rows} '
              'grid=${grid.columns}x${grid.rows} ---\n'
              '${session.probe.describeProbeWindow(scanRows: viewport.rows)}');

          // Unique marker so a matched needle can only be our just-sent text,
          // never a codex placeholder / tip row.
          final text = 'codex-probe-${DateTime.now().millisecondsSinceEpoch}';
          final automation = FullscreenPtyAutomation();
          final port = TerminalFullscreenPtyPort(
            input: session.input,
            probe: session.probe,
            aborted: () => false,
            composerRegion: const CodexTerminalBehavior().composerRegion,
          );
          final outcome = await automation.deliverPasteAndSubmit(
            port: port,
            text: text,
            pasteSettle: const Duration(milliseconds: 150),
          );

          await session.probe.syncDisplayGrid();
          final afterDeliver = session.probe.describeProbeWindow(scanRows: viewport.rows);
          // ignore: avoid_print
          print('--- deliver outcome=$outcome ---\n$afterDeliver');

          expect(
            outcome,
            FullscreenPtyDeliveryOutcome.submitted,
            reason: 'codex regionMovedDown ACK must pass at '
                '${viewport.cols}x${viewport.rows}. Dump:\n$afterDeliver',
          );
        },
      );
    }
  });
}
