import '../../../workspace_dnd/path_reference_formatter.dart';
import '../../../terminal/fullscreen_cr_ack_config.dart';
import '../../../terminal/fullscreen_input_readiness.dart';
import '../cli_capability.dart';

/// How a dropped file path is injected into a CLI's input box.
enum TerminalPathDropMode {
  /// Write the text straight to the PTY with no trailing CR. Suits line-edited
  /// input where raw bytes land at the cursor.
  rawAppend,

  /// Wrap the text in bracketed-paste markers and send no CR, so a full-screen
  /// TUI (Claude Code's Ink box, Cursor) inserts it without submitting.
  bracketedNoSubmit,
}

/// Per-CLI rules for turning a dragged path into input-box text. Keeps path
/// drag-and-drop free of `if (cli == …)` branching — each CLI declares how it
/// wants a path quoted and delivered.
class TerminalPathDropBehavior {
  const TerminalPathDropBehavior({required this.mode, required this.quoting});

  final TerminalPathDropMode mode;
  final PathQuoting quoting;

  /// Sensible default derived from full-screen input: TUIs need bracketed paste
  /// without submit; line-edited CLIs take a raw append. POSIX quote-if-needed.
  factory TerminalPathDropBehavior.defaultFor({
    required bool usesFullScreenInput,
  }) => TerminalPathDropBehavior(
    mode: usesFullScreenInput
        ? TerminalPathDropMode.bracketedNoSubmit
        : TerminalPathDropMode.rawAppend,
    quoting: PathQuoting.posixQuoteIfNeeded,
  );
}

abstract interface class TerminalBehaviorCapability implements CliCapability {
  bool get supportsTurnInterrupt;

  TurnInterruptPlan get interruptPlan;

  bool get usesFullScreenInput;

  /// Delay between bracketed-paste content and the standalone CR in
  /// [TerminalInputController.submitFullScreenInput]. Claude Ink settles in ~10ms;
  /// Cursor's agent TUI needs longer or the CR is coalesced into the paste.
  Duration get fullScreenPasteSettleDelay;

  /// Whether full-screen inject should content-ACK on the mirror grid before CR.
  /// False falls back to timed paste+CR for TUIs that stage input without
  /// echoing it into PTY output (none of the built-in CLIs currently need it).
  bool get usesGridPasteAck;

  /// How a file dropped onto this CLI's terminal is quoted and injected.
  TerminalPathDropBehavior get pathDropBehavior;

  /// How grid automation ACKs a CR after paste. Most TUIs clear the anchor
  /// cell; codex keeps the line as history and paints a new composer below.
  FullscreenCrAckStrategy get fullscreenCrAckStrategy;

  /// Leading prefix on mirror-grid rows that identify composer chrome (`→`, `›`,
  /// `❯`, `┃`, …). Used to scope paste needle search away from stale transcript
  /// on tall viewports, and required for
  /// [FullscreenCrAckStrategy.composerMovesDown] CR ACK.
  String? get fullscreenComposerPrefix;

  /// When the TUI is ready for paste+CR. Default is boot-frame-only.
  FullscreenInputReadiness get inputReadiness;

  /// How long [TerminalLaunchController] waits for first PTY paint.
  ///
  /// Cursor cold starts often exceed 15s while plugins and the model catalog
  /// load; other CLIs keep the historical 15s default.
  Duration get startupDeadline;
}

final class TurnInterruptPlan {
  const TurnInterruptPlan({
    required this.steps,
    this.gapBetweenSteps = Duration.zero,
  });

  final List<String> steps;
  final Duration gapBetweenSteps;
}

/// Default v1 plan: Ctrl+C once.
final class CtrlCTurnInterrupt implements CliCapability {
  const CtrlCTurnInterrupt();

  bool get supportsTurnInterrupt => true;

  TurnInterruptPlan get interruptPlan =>
      const TurnInterruptPlan(steps: ['\x03']);
}
