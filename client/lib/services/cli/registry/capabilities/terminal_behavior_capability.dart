import '../../../workspace_dnd/path_reference_formatter.dart';
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
  bool get usesFullScreenInput;

  /// Whether the embedded terminal may forward the OSC 997 color-scheme report
  /// (mode 2031) to this CLI's TUI. Most CLIs use it for live light/dark
  /// theming; Cursor's TUI mishandles it (the report leaks into its input box),
  /// so it is stripped for cursor.
  bool get forwardsColorSchemeReport;

  /// How a file dropped onto this CLI's terminal is quoted and injected.
  TerminalPathDropBehavior get pathDropBehavior;
}
