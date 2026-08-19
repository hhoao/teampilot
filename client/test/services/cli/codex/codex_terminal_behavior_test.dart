import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/cli/claude/capabilities/terminal_behavior.dart';
import 'package:teampilot/services/cli/codex/capabilities/terminal_behavior.dart';
import 'package:teampilot/services/cli/cursor/capabilities/terminal_behavior.dart';
import 'package:teampilot/services/terminal/fullscreen_cr_ack_config.dart';
import 'package:teampilot/services/terminal/fullscreen_input_readiness.dart';

void main() {
  group('CodexTerminalBehavior', () {
    const behavior = CodexTerminalBehavior();

    test('uses Cursor-length paste settle so CR is not swallowed into paste', () {
      expect(
        behavior.fullScreenPasteSettleDelay,
        const Duration(milliseconds: 150),
      );
      expect(
        behavior.fullscreenCrAckStrategy,
        FullscreenCrAckStrategy.composerMovesDown,
      );
    });

    test('input surface is not ready on splash or trust screens', () {
      expect(
        behavior.inputReadiness.isReady(
          'Welcome to Codex\nPress enter to continue',
        ),
        isFalse,
      );
      expect(
        behavior.inputReadiness.isReady('Do you trust this directory?'),
        isFalse,
      );
    });

    test('input surface is ready when status footer or composer paints', () {
      expect(
        behavior.inputReadiness.isReady('gpt-5.6-luna default · /opt/dsd'),
        isTrue,
      );
      expect(behavior.inputReadiness.isReady('› '), isTrue);
    });

    test('boot-gate needles match Codex first-run screens', () {
      expect(
        behavior.inputReadiness.needsBootGateNudge(
          'Press enter to continue',
        ),
        isTrue,
      );
      expect(
        behavior.inputReadiness.needsBootGateNudge('› hello'),
        isFalse,
      );
    });
  });

  test('Claude does not wait for composer chrome beyond boot frame', () {
    expect(
      const ClaudeTerminalBehavior().inputReadiness.waitsForSurface,
      isFalse,
    );
  });

  test('Cursor waits for its composer arrow', () {
    const cursor = CursorTerminalBehavior();
    expect(cursor.inputReadiness.waitsForSurface, isTrue);
    expect(cursor.inputReadiness.isReady('thinking'), isFalse);
    expect(cursor.inputReadiness.isReady('→ Plan, search'), isTrue);
  });

  test('isTerminalInputSurfaceReady treats missing readiness as boot-only', () {
    expect(
      isTerminalInputSurfaceReady(readiness: null, probeWindow: ''),
      isTrue,
    );
  });
}
