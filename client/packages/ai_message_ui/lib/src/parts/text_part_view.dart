import 'dart:async';

import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter/material.dart';
import 'package:tp_markdown/tp_markdown.dart';

import '../history_render_scope.dart';
import '../message_role_scope.dart';
import '../message_streaming_scope.dart';
import '../strings.dart';
import '../theme.dart';
import 'fade_expand_body.dart';

/// Used by [AiTextPartView.onTapLink].
typedef MarkdownTapLinkCallback = void Function(
  String text,
  String? href,
  String title,
);

/// Streaming-safe markdown aligned with assistant-ui MarkdownText / aui-md.
///
/// Compiles GFM via [compileMarkdown] (cached) and renders with
/// [MarkdownView] (compact profile from [AiMessageTheme.markdown]). Under
/// [AiHistoryRenderScope], long content follows Claude Code webview `oYe`
/// (budgeted IR + Show more / Show less) — widgets beyond the budget are omitted
/// so Flutter does not layout them.
///
/// While [AiMessageStreamingScope.streaming] is true, compile is throttled
/// (~80ms) so tip growth does not re-parse GFM every frame; complete messages
/// always compile immediately.
class AiTextPartView extends StatefulWidget {
  const AiTextPartView({
    required this.text,
    this.onTapLink,
    super.key,
  });

  final String text;

  /// Optional; package does not launch URLs itself.
  final MarkdownTapLinkCallback? onTapLink;

  /// Tip streaming throttle window.
  @visibleForTesting
  static const Duration streamingCompileThrottle = Duration(milliseconds: 80);

  @override
  State<AiTextPartView> createState() => _AiTextPartViewState();
}

class _AiTextPartViewState extends State<AiTextPartView> {
  /// Raw text beyond this length is not fully compiled while collapsed in
  /// history review — a clipped preview source is compiled instead, so opening
  /// a giant message (e.g. a bundled-skill user turn) does not hitch the frame
  /// with a full parse (~0.5 s at 785 KB).
  static const _kHardCompileThreshold = 20000;
  static const _kPreviewCompileChars = 8000;

  late String _compiledText;
  late MarkdownDocument _document;
  String? _pendingText;
  Timer? _throttle;
  bool? _lastStreaming;
  /// Captured in [didChangeDependencies] (inherited lookups are not safe from
  /// the streaming throttle timer). Used by [_previewSource].
  var _inHistoryScope = false;
  /// Message role — user messages collapse as whole pastes; assistant prose
  /// renders fully inline (never clipped).
  var _role = AiRole.assistant;
  /// User-message display mode — `flatten` needs the full doc immediately (no
  /// mask), so oversized user text is not clip-compiled in that mode.
  var _userMessageMode = ContentDisplayMode.foldFixedHeight;
  var _initialized = false;
  /// True when [_document] was compiled from a preview clip (not the full
  /// [widget.text]) — the full doc is compiled lazily on expand.
  var _compiledClip = false;

  @override
  void initState() {
    super.initState();
    // No compile here — didChangeDependencies picks the preview/full source
    // using the history scope, which is not available before mount.
    _compiledText = '';
    _document = const MarkdownDocument(blocks: []);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final streaming = AiMessageStreamingScope.of(context);
    final inHistory = AiHistoryRenderScope.maybeOf(context) != null;
    final role = AiMessageRoleScope.of(context);
    final userMode = MarkdownDisplayModeScope.userMessageOf(context);
    if (_initialized &&
        streaming == _lastStreaming &&
        inHistory == _inHistoryScope &&
        role == _role &&
        userMode == _userMessageMode) {
      return;
    }
    _lastStreaming = streaming;
    _inHistoryScope = inHistory;
    _role = role;
    _userMessageMode = userMode;
    if (!_initialized) {
      _initialized = true;
      // First sync: compile synchronously (scope-aware source) so the first
      // frame renders content instead of waiting for a streaming throttle.
      _commit(widget.text);
      return;
    }
    _syncDocument(widget.text, streaming: streaming);
  }

  @override
  void didUpdateWidget(covariant AiTextPartView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      _syncDocument(
        widget.text,
        streaming: _lastStreaming ?? AiMessageStreamingScope.of(context),
      );
    }
  }

  @override
  void dispose() {
    _throttle?.cancel();
    super.dispose();
  }

  /// Source to compile for [text]. While streaming, or outside a history scope,
  /// compile the full text. In history review, oversized **user** messages
  /// compile only a preview clip (fast) — the full doc is compiled lazily on
  /// expand. Assistant prose always compiles fully (it renders inline).
  String _previewSource(String text) {
    if (text.length <= _kHardCompileThreshold) return text;
    if (_lastStreaming ?? false) return text;
    if (!_inHistoryScope) return text;
    if (_role != AiRole.user) return text;
    if (_userMessageMode == ContentDisplayMode.flatten) return text;
    return text.substring(0, _kPreviewCompileChars);
  }

  void _syncDocument(String text, {required bool streaming}) {
    if (!streaming) {
      _throttle?.cancel();
      _throttle = null;
      _pendingText = null;
      _commit(text);
      return;
    }

    _pendingText = text;
    if (_compiledText == text) return;
    if (_throttle?.isActive ?? false) return;
    _throttle = Timer(AiTextPartView.streamingCompileThrottle, () {
      final pending = _pendingText;
      if (pending == null || !mounted) return;
      _commit(pending);
    });
  }

  void _commit(String text) {
    if (_compiledText == text) return;
    final source = _previewSource(text);
    final doc = compileMarkdown(source);
    _compiledText = text;
    _compiledClip = source != text;
    _document = doc;
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final scope = AiHistoryRenderScope.maybeOf(context);
    if (scope == null) {
      return _ChatMarkdownView(
        document: _document,
        onTapLink: widget.onTapLink,
      );
    }
    return _ExpandableHistoryMarkdown(
      document: _document,
      fullText: widget.text,
      clipped: _compiledClip,
      onTapLink: widget.onTapLink,
      budget: scope.contentBudget,
      streaming: AiMessageStreamingScope.of(context),
    );
  }
}

MarkdownResolvers _chatResolvers(MarkdownTapLinkCallback? onTapLink) {
  if (onTapLink == null) return const MarkdownResolvers();
  return MarkdownResolvers(
    onLinkTap: (href) => onTapLink('', href, ''),
  );
}

MarkdownStrings _chatMarkdownStrings(BuildContext context) {
  final s = AiMessageStrings.of(context);
  return MarkdownStrings(
    copy: s.copy,
    copied: s.copied,
    code: s.code,
    showMore: s.showMore,
    showLess: s.showLess,
  );
}

class _ChatMarkdownView extends StatelessWidget {
  const _ChatMarkdownView({
    required this.document,
    this.onTapLink,
  });

  final MarkdownDocument document;
  final MarkdownTapLinkCallback? onTapLink;

  @override
  Widget build(BuildContext context) {
    final theme = AiMessageTheme.of(context);
    return MarkdownView(
      document: document,
      tokens: theme.markdown,
      resolvers: _chatResolvers(onTapLink),
      strings: _chatMarkdownStrings(context),
    );
  }
}

/// Claude Code `oYe`-aligned expandable markdown (IR omit, not CSS clip).
class _ExpandableHistoryMarkdown extends StatefulWidget {
  const _ExpandableHistoryMarkdown({
    required this.document,
    required this.budget,
    required this.fullText,
    required this.clipped,
    this.onTapLink,
    this.streaming = false,
  });

  final MarkdownDocument document;
  final ContentCollapseBudget budget;

  /// Raw full text. When [clipped], [document] is a preview clip and this is
  /// compiled lazily on "Show more" (so opening never parses the whole text).
  final String fullText;

  /// True when [document] was compiled from a preview clip, not [fullText].
  final bool clipped;

  final MarkdownTapLinkCallback? onTapLink;

  /// While a message is still streaming, render fully (the user is watching it
  /// grow) — the budget collapse applies only once the message is complete.
  final bool streaming;

  @override
  State<_ExpandableHistoryMarkdown> createState() =>
      _ExpandableHistoryMarkdownState();
}

/// Expanded docs with at least this many top-level blocks render inside the
/// virtualized (bounded, internally-scrolling) markdown view instead of a plain
/// full Column.
const int kVirtualizeMarkdownBlockThreshold = 80;

/// Collapsed mask height for an oversized user message (Claude webview `oYe`
/// uses ~250 px).
const double kMaskCollapsedMaxHeight = 260;

/// Finder key for the "collapse back" bar under an expanded user message.
const Key kMaskCollapseBarKey = ValueKey('ai-mask-collapse-bar');

class _ExpandableHistoryMarkdownState extends State<_ExpandableHistoryMarkdown> {
  var _expanded = false;
  MarkdownDocument? _fullDocument;

  @override
  void didUpdateWidget(covariant _ExpandableHistoryMarkdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.document != widget.document ||
        oldWidget.fullText != widget.fullText) {
      _expanded = false;
      _fullDocument = null;
    }
  }

  void _toggle() {
    setState(() {
      _expanded = !_expanded;
      if (_expanded && widget.clipped && _fullDocument == null) {
        // User-initiated full render — a synchronous parse of a very large
        // text is acceptable here (only paid when the user asks to see it).
        _fullDocument = compileMarkdown(widget.fullText);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.streaming) {
      return _ChatMarkdownView(
        document: widget.document,
        onTapLink: widget.onTapLink,
      );
    }

    // Assistant (and system) prose never collapses — render fully inline.
    // Oversized code blocks are capped per-block inside _MarkdownCodeBlock.
    if (AiMessageRoleScope.of(context) != AiRole.user) {
      return _ChatMarkdownView(
        document: widget.document,
        onTapLink: widget.onTapLink,
      );
    }

    // User message: whole-message collapse, per display mode.
    final userMode = MarkdownDisplayModeScope.userMessageOf(context);
    if (userMode == ContentDisplayMode.flatten) {
      // Always natural height in the flow — no mask, no bounded panel.
      final flattened = widget.clipped
          ? (_fullDocument ?? widget.document)
          : widget.document;
      return _buildFlattenMarkdown(context, flattened);
    }

    final truncated = truncateMessageContent(
      widget.document,
      budget: widget.budget,
    );
    if (!widget.clipped && !truncated.wasTruncated) {
      return _ChatMarkdownView(
        document: widget.document,
        onTapLink: widget.onTapLink,
      );
    }

    if (!_expanded) {
      // Masked preview: budgeted content clipped to a teaser with a bottom
      // fade + chevron. `forceChrome` keeps the mask even for a short preview
      // (there is always more content behind the expand action).
      return AiFadeExpandBody(
        open: false,
        onToggle: _toggle,
        fadeColor: AiMessageTheme.of(context).resolveUserBubble(
          Theme.of(context).colorScheme,
        ),
        collapsedMaxHeight: kMaskCollapsedMaxHeight,
        forceChrome: true,
        child: _ChatMarkdownView(
          document: truncated.wasTruncated
              ? truncated.document
              : widget.document,
          onTapLink: widget.onTapLink,
        ),
      );
    }

    // Expanded: full content + collapse bar.
    final expandedDoc = widget.clipped
        ? (_fullDocument ?? widget.document)
        : widget.document;
    final Widget body;
    if (userMode == ContentDisplayMode.foldExpandFull) {
      // Mask → expand to full natural height in the flow (no bounded panel).
      body = _buildFlattenMarkdown(context, expandedDoc);
    } else {
      final bool huge =
          widget.clipped ||
          expandedDoc.blocks.length >= kVirtualizeMarkdownBlockThreshold;
      body = huge
          ? VirtualMarkdownView(
              document: expandedDoc,
              tokens: AiMessageTheme.of(context).markdown,
              resolvers: _chatResolvers(widget.onTapLink),
              strings: _chatMarkdownStrings(context),
              maxHeight: (MediaQuery.sizeOf(context).height * 0.7).clamp(
                240.0,
                800.0,
              ),
            )
          : _ChatMarkdownView(
              document: expandedDoc,
              onTapLink: widget.onTapLink,
            );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        body,
        _MaskCollapseBar(
          onTap: _toggle,
          fadeColor: AiMessageTheme.of(context).resolveUserBubble(
            Theme.of(context).colorScheme,
          ),
        ),
      ],
    );
  }

  Widget _buildFlattenMarkdown(BuildContext context, MarkdownDocument doc) {
    return VirtualMarkdownView(
      document: doc,
      tokens: AiMessageTheme.of(context).markdown,
      resolvers: _chatResolvers(widget.onTapLink),
      strings: _chatMarkdownStrings(context),
      flatten: true,
    );
  }
}

/// Bottom "collapse back" chevron bar under an expanded user message.
class _MaskCollapseBar extends StatelessWidget {
  const _MaskCollapseBar({required this.onTap, required this.fadeColor});

  final VoidCallback onTap;
  final Color fadeColor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: 'Collapse',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          key: kMaskCollapseBarKey,
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: SizedBox(
            height: 40,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          fadeColor.withValues(alpha: 0),
                          fadeColor.withValues(alpha: 0.85),
                        ],
                      ),
                    ),
                  ),
                ),
                Icon(
                  Icons.keyboard_arrow_up_rounded,
                  size: 20,
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
