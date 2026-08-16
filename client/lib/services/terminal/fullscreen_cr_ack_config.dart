/// How full-screen PTY automation confirms a CR submit on the mirror grid.
enum FullscreenCrAckStrategy {
  /// [isFullscreenPromptAtAnchor] must become false (claude, cursor, opencode).
  anchorCellClears,

  /// Staged text stays on [FullscreenPromptAnchor.row] as history; a new
  /// [FullscreenCrAckConfig.composerPrefix] row appears below (codex).
  composerMovesDown,

  /// Skip grid polling after CR; rely on paste settle timing only.
  timed,
}

/// Per-CLI CR submit ACK rules for [FullscreenPtyAutomation].
final class FullscreenCrAckConfig {
  const FullscreenCrAckConfig({
    this.strategy = FullscreenCrAckStrategy.anchorCellClears,
    this.composerPrefix,
  });

  const FullscreenCrAckConfig.productionDefault()
    : strategy = FullscreenCrAckStrategy.anchorCellClears,
      composerPrefix = null;

  final FullscreenCrAckStrategy strategy;

  /// Row-leading prefix that marks composer chrome on the mirror grid. Scopes
  /// paste needle search on tall viewports and is required for
  /// [FullscreenCrAckStrategy.composerMovesDown].
  final String? composerPrefix;
}
