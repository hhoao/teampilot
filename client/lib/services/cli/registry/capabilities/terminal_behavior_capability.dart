import '../cli_capability.dart';

abstract interface class TerminalBehaviorCapability implements CliCapability {
  bool get usesFullScreenInput;

  /// Whether the embedded terminal may forward the OSC 997 color-scheme report
  /// (mode 2031) to this CLI's TUI. Most CLIs use it for live light/dark
  /// theming; Cursor's TUI mishandles it (the report leaks into its input box),
  /// so it is stripped for cursor.
  bool get forwardsColorSchemeReport;
}
