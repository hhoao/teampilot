/// The terminal-write surface the drop ingestor needs, narrowed to the two
/// injection styles a dropped path uses. `TerminalSession` implements it;
/// tests supply a fake so the ingestor is exercised without a PTY.
abstract interface class TerminalTextSink {
  /// Write [text] straight to the PTY with no trailing CR.
  void appendText(String text);

  /// Insert [text] into a full-screen TUI's input box via bracketed paste,
  /// sending no CR so it is staged but not submitted.
  Future<void> pasteWithoutSubmit(String text);
}
