/// How full-screen PTY automation confirms a CR submit on the mirror grid.
enum FullscreenCrAckStrategy {
  /// [isFullscreenPromptAtAnchor] must become false (claude, cursor, opencode).
  anchorCellClears,

  /// Staged text stays on [FullscreenPromptAnchor.row] as history; a new
  /// input row appears below (codex).
  /// Not submitted while [needle] is still the body of the input box.
  composerMovesDown,

  /// Skip grid polling after CR; rely on paste settle timing only.
  timed,
}

/// Per-CLI CR submit ACK rules for [FullscreenPtyAutomation].
final class FullscreenCrAckConfig {
  const FullscreenCrAckConfig({
    this.strategy = FullscreenCrAckStrategy.anchorCellClears,
    this.hookSubmitAck = false,
  });

  const FullscreenCrAckConfig.productionDefault()
    : strategy = FullscreenCrAckStrategy.anchorCellClears,
      hookSubmitAck = false;

  final FullscreenCrAckStrategy strategy;

  /// When true, the CR submit is confirmed **only** by the hook
  /// `promptSubmitted` signal ([FullscreenPtyDeliveryPort] `isAcked`); the
  /// mirror grid is still used to ACK the paste but is NOT consulted for the
  /// submit verdict.
  ///
  /// Grid submit probing is unreliable on resumed sessions (an identical older
  /// message in the transcript can be mistaken for the staged line and report
  /// `submitted` while the CLI never received the new prompt). Every built-in
  /// CLI emits a submit hook (`UserPromptSubmit` / `beforeSubmitPrompt` /
  /// `userMessageSubmitted`), so hook ack is authoritative.
  final bool hookSubmitAck;
}
