/// How a full-screen TUI confirms a CR submit on the mirror grid.
enum ComposerSubmitSemantics {
  /// Staged input vanished from the composer region (claude, flashskyai,
  /// opencode — was anchorCellClears).
  regionCleared,

  /// Staged text stays on-screen as history; a new composer region appears
  /// below (cursor, codex — was composerMovesDown).
  regionMovedDown,

  /// Skip grid polling after CR; rely on paste settle timing only.
  timed,
}

/// Candidate border glyphs for boxed composer regions (opencode: `┃`/`▀`/`╹`).
final class ComposerBorderSpec {
  const ComposerBorderSpec({
    this.left = const [],
    this.bottom = const [],
    this.corner = const [],
  });

  final List<String> left;
  final List<String> bottom;
  final List<String> corner;
}

/// Per-CLI staged-input region declaration for full-screen PTY automation.
final class FullscreenComposerRegionSpec {
  const FullscreenComposerRegionSpec({
    required this.submitSemantics,
    this.prefixes = const [],
    this.border = const ComposerBorderSpec(),
  });

  final ComposerSubmitSemantics submitSemantics;

  /// Row-leading prefix candidates that mark composer chrome (`❯`, `→`, `›`,
  /// `┃`, …). The region is the lowest prefix row plus consecutive prefix
  /// rows above it; boxed CLIs also supply [border].
  final List<String> prefixes;

  /// Box border candidates (opencode). When a left-border column is found,
  /// the region is the rectangle spanned by left border + bottom border row.
  final ComposerBorderSpec border;
}

const fullscreenDefaultComposerSpec = FullscreenComposerRegionSpec(
  submitSemantics: ComposerSubmitSemantics.regionCleared,
);

const fullscreenTimedComposerSpec = FullscreenComposerRegionSpec(
  submitSemantics: ComposerSubmitSemantics.timed,
);
