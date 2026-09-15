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
    this.pasteBaseline = false,
  });

  const FullscreenCrAckConfig.productionDefault()
    : strategy = FullscreenCrAckStrategy.anchorCellClears,
      hookSubmitAck = false,
      pasteBaseline = false;

  final FullscreenCrAckStrategy strategy;

  /// When true, paste ACK uses the paste-denominator baseline flow: locate the
  /// needle in the bottom input zone AFTER the composer clear (any leftover
  /// transcript echo), then reject a post-paste anchor at or above that row.
  ///
  /// cursor-agent's mirror terminal caret sits on an empty composer line below
  /// its box — the cursor input zone (`[caret-4, caret]`) starts inside the
  /// paste and misses the needle's leading row, so pastes never ACK and the
  /// message clears+re-pastes forever. Cursor uses the bottom-scan baseline
  /// instead; other built-in CLIs use the cursor input zone.
  final bool pasteBaseline;

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
