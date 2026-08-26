import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../ir/markdown_block_kind.dart';
import '../ir/markdown_document.dart';
import '../registry/block_widget_registry.dart';
import '../registry/markdown_resolvers.dart';
import '../strings.dart';
import '../tokens/markdown_tokens.dart';
import 'highlight_context.dart';
import 'inline_spans.dart';

/// Controller bound to one [VirtualMarkdownView]; reveals blocks by scrolling
/// the owning viewport (internal in bounded mode, parent scroll in flatten).
class MarkdownViewController {
  _VirtualMarkdownViewState? _state;

  bool get hasClients => _state != null;

  Future<void> revealBlock(int blockIndex) async {
    await _state?.revealBlockPublic(blockIndex);
  }

  /// Detach without disposing the bound view (safe to call repeatedly).
  void dispose() {
    if (_state != null) {
      _state = null;
    }
  }

  void _attachInternal(_VirtualMarkdownViewState s) => _state = s;

  void _detachInternal(_VirtualMarkdownViewState s) {
    if (identical(_state, s)) _state = null;
  }
}

/// Block-level virtualized markdown renderer for very large documents.
///
/// [MarkdownView] lays out every block in a [Column], which freezes the frame
/// for a single very large message (e.g. a bundled-skill user turn). This view
/// instead keeps a height cache per layout unit (a merged paragraph run or a
/// single block) and mounts only the units in the scroll viewport (+ overscan),
/// recycling on scroll.
///
/// Two modes:
/// - **bounded** (default): owns a `SingleChildScrollView` capped at [maxHeight]
///   — Monaco-style panel with its own scrollbar.
/// - **flatten** ([flatten] = true): renders at **natural height inside the
///   parent scroll** (no own scrollbar, no max-height), reading the parent's
///   scroll position + own viewport offset to mount only visible blocks — VS
///   Code markdown preview-style flow; the parent owns scrolling.
///
/// Renders the same blocks as [MarkdownView] (registry + tokens + gaps), just
/// lazily.
class VirtualMarkdownView extends StatefulWidget {
  const VirtualMarkdownView({
    super.key,
    required this.document,
    required this.tokens,
    this.resolvers = const MarkdownResolvers(),
    this.strings = MarkdownStrings.english,
    this.registry,
    this.maxHeight = 480,
    this.estimateHeight = 44,
    this.overscan = 6,
    this.flatten = false,
    this.highlights,
    this.controller,
  });

  final MarkdownDocument document;
  final MarkdownTokens tokens;
  final MarkdownResolvers resolvers;
  final MarkdownStrings strings;
  final BlockWidgetRegistry? registry;

  /// Cap on the internal scroll viewport (the panel height). Ignored when
  /// [flatten] is true.
  final double maxHeight;

  /// Per-unit height used before a unit has been measured.
  final double estimateHeight;

  /// Extra units mounted beyond the visible range.
  final int overscan;

  /// When true, render at **natural height inside the parent scroll** (no own
  /// scrollbar, no max-height), mounting only the blocks visible in the parent
  /// viewport. VS Code markdown preview-style flow; the parent owns scrolling.
  final bool flatten;

  /// Optional match-highlight resolver, looked up per top-level block index
  /// while units build their spans.
  final MarkdownHighlightContext? highlights;

  /// Optional controller for programmatic reveal (e.g. jumping to a search
  /// hit). See [MarkdownViewController.revealBlock].
  final MarkdownViewController? controller;

  @override
  State<VirtualMarkdownView> createState() => _VirtualMarkdownViewState();
}

class _VirtualMarkdownViewState extends State<VirtualMarkdownView> {
  late final ScrollController _scrollController;
  late List<_MarkdownUnit> _units;
  late _BlockHeightCache _cache;
  final List<TapGestureRecognizer> _linkRecognizers = [];

  int _firstIndex = 0;
  int _lastIndex = -1;
  double _paddingTop = 0;
  double _paddingBottom = 0;

  bool _correctionScheduled = false;
  double _pendingCorrection = 0;

  /// Monotonic reveal generation: rapid n/N navigation supersedes in-flight
  /// reveals, and an older reveal's second-pass correction must not fire after
  /// a newer one started (it would jump scroll back).
  int _revealEpoch = 0;

  /// Parent scroll position we follow in [flatten] mode (the parent's
  /// `Scrollable`); null in bounded mode.
  ScrollPosition? _parentPosition;

  @override
  void initState() {
    super.initState();
    widget.controller?._attachInternal(this);
    _scrollController = ScrollController();
    _cache = _BlockHeightCache(estimate: widget.estimateHeight);
    _units = _computeUnits(widget.document);
    _scrollController.addListener(_onScroll);
    _syncVisibleRange();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _syncVisibleRange();
      if (widget.flatten) {
        // Our viewport offset is only meaningful after the parent laid us out.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _syncVisibleRange();
        });
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _bindParentScroll();
  }

  @override
  void didUpdateWidget(covariant VirtualMarkdownView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?._detachInternal(this);
      widget.controller?._attachInternal(this);
    }
    if (oldWidget.flatten != widget.flatten) {
      _bindParentScroll();
    }
    // Units capture the highlight context in their build closures, so any
    // highlight swap must recompute them. Heights stay cached across
    // highlight-only changes — background wash never affects layout.
    if (!identical(oldWidget.highlights, widget.highlights) ||
        oldWidget.document != widget.document) {
      _units = _computeUnits(widget.document);
      if (oldWidget.document != widget.document) {
        _cache.invalidateAll();
        _firstIndex = 0;
        _lastIndex = -1;
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(0);
        }
      }
      _syncVisibleRange();
    }
  }

  void _bindParentScroll() {
    if (!widget.flatten) {
      if (_parentPosition != null) {
        _parentPosition!.removeListener(_onScroll);
        _parentPosition = null;
      }
      return;
    }
    final position = Scrollable.maybeOf(context)?.position;
    if (identical(position, _parentPosition)) return;
    _parentPosition?.removeListener(_onScroll);
    _parentPosition = position;
    _parentPosition?.addListener(_onScroll);
  }

  @override
  void dispose() {
    widget.controller?._detachInternal(this);
    _parentPosition?.removeListener(_onScroll);
    _disposeRecognizers(_linkRecognizers);
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  // --- Unit precomputation (mirrors MarkdownView's build loop) -------------

  List<_MarkdownUnit> _computeUnits(MarkdownDocument document) {
    final blocks = document.blocks;
    final units = <_MarkdownUnit>[];
    MarkdownBlock? previous;
    var i = 0;
    while (i < blocks.length) {
      final block = blocks[i];
      if (block is ParagraphBlock) {
        var end = i + 1;
        while (end < blocks.length && blocks[end] is ParagraphBlock) {
          end++;
        }
        final run = blocks.sublist(i, end).cast<ParagraphBlock>();
        final first = i;
        final last = end - 1;
        final context = widget.highlights;
        units.add(
          _MarkdownUnit(
            kind: MarkdownBlockKind.paragraph,
            gapBefore: _gapBefore(previous?.kind, MarkdownBlockKind.paragraph),
            firstBlockIndex: first,
            lastBlockIndex: last,
            build: (tokens, resolvers, strings, reg) {
              final perParagraph = [
                for (var p = 0; p < run.length; p++)
                  context?.forContainer(first + p, const []),
              ];
              return run.length == 1
                  ? buildParagraph(run.first, tokens, resolvers,
                      highlights: perParagraph[0])
                  : buildMergedParagraphs(run, tokens, resolvers,
                      highlights: perParagraph);
            },
          ),
        );
        previous = run.last;
        i = end;
        continue;
      }

      final currentIndex = i;
      units.add(
        _MarkdownUnit(
          kind: block.kind,
          gapBefore: _gapBefore(previous?.kind, block.kind),
          firstBlockIndex: currentIndex,
          lastBlockIndex: currentIndex,
          build: (tokens, resolvers, strings, reg) => reg.build(
            block,
            tokens,
            resolvers,
            strings,
            highlights: widget.highlights,
            blockIndex: currentIndex,
            basePath: const [],
          ),
        ),
      );
      previous = block;
      i++;
    }
    return units;
  }

  double _gapBefore(MarkdownBlockKind? previous, MarkdownBlockKind next) =>
      previous == null ? 0 : gapBetween(previous, next, widget.tokens);

  /// Index of the unit covering [blockIndex], or -1.
  int _unitForBlock(int blockIndex) {
    var lo = 0;
    var hi = _units.length - 1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      final unit = _units[mid];
      if (blockIndex < unit.firstBlockIndex) {
        hi = mid - 1;
      } else if (blockIndex > unit.lastBlockIndex) {
        lo = mid + 1;
      } else {
        return mid;
      }
    }
    return -1;
  }

  // --- Link recognizer lifecycle (mirrors MarkdownView) --------------------

  void _disposeRecognizers(List<TapGestureRecognizer> recognizers) {
    for (final recognizer in recognizers) {
      recognizer.dispose();
    }
    recognizers.clear();
  }

  MarkdownResolvers _resolversForBuild() {
    if (_linkRecognizers.isNotEmpty) {
      final retiring = List<TapGestureRecognizer>.of(_linkRecognizers);
      _linkRecognizers.clear();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _disposeRecognizers(retiring);
      });
    }
    final onLinkTap = widget.resolvers.onLinkTap;
    if (onLinkTap == null) return widget.resolvers;
    return MarkdownResolvers(
      onLinkTap: onLinkTap,
      resolveImage: widget.resolvers.resolveImage,
      createLinkRecognizer: (href) {
        final recognizer = TapGestureRecognizer()..onTap = () => onLinkTap(href);
        _linkRecognizers.add(recognizer);
        return recognizer;
      },
    );
  }

  // --- Scroll / range -------------------------------------------------------

  void _onScroll() => _syncVisibleRange();

  void _syncVisibleRange() {
    if (!mounted || _units.isEmpty) return;
    if (widget.flatten) {
      _syncFlattenRange();
      return;
    }
    if (!_scrollController.hasClients ||
        !_scrollController.position.hasViewportDimension) {
      final count = widget.overscan.clamp(1, _units.length);
      _applyRange(
        _BlockVisibleRange(
          firstIndex: 0,
          lastIndex: count - 1,
          paddingTop: 0,
          paddingBottom:
              _cache.totalExtent(_units.length) -
              _cache.offsetBefore(_units.length, count),
        ),
      );
      return;
    }

    final position = _scrollController.position;
    final range = _cache.visibleRange(
      unitCount: _units.length,
      scrollPixels: position.pixels,
      viewportHeight: position.viewportDimension,
      overscan: widget.overscan,
    );
    final clamped = _cache.clampUnmeasuredMounts(
      unitCount: _units.length,
      range: range,
      maxUnmeasured: widget.overscan,
      preferEnd: _scrolledNearEnd(position.pixels),
    );
    _applyRange(clamped);
  }

  /// Flatten mode: compute the visible block window from the **parent** scroll.
  /// Our offset in the parent viewport comes from [RenderAbstractViewport]; the
  /// visible document range is `[parentPixels - myOffset, +viewportHeight]`.
  void _syncFlattenRange() {
    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) {
      // Cold: mount a small window at the top on the estimated extent.
      final count = widget.overscan.clamp(1, _units.length);
      _applyRange(
        _BlockVisibleRange(
          firstIndex: 0,
          lastIndex: count - 1,
          paddingTop: 0,
          paddingBottom:
              _cache.totalExtent(_units.length) -
              _cache.offsetBefore(_units.length, count),
        ),
      );
      return;
    }
    final viewport = RenderAbstractViewport.of(renderObject);
    final pixels = _parentPosition?.pixels ?? 0.0;
    final revealed = viewport.getOffsetToReveal(renderObject, 0.0);
    final visibleTop = pixels - revealed.offset;
    final viewportHeight = _parentPosition?.viewportDimension ?? 0.0;
    final range = _cache.visibleRange(
      unitCount: _units.length,
      scrollPixels: visibleTop,
      viewportHeight: viewportHeight,
      overscan: widget.overscan,
    );
    final clamped = _cache.clampUnmeasuredMounts(
      unitCount: _units.length,
      range: range,
      maxUnmeasured: widget.overscan,
      preferEnd: _flattenNearEnd(pixels, viewportHeight),
    );
    _applyRange(clamped);
  }

  bool _flattenNearEnd(double pixels, double viewportHeight) {
    final p = _parentPosition;
    if (p == null) return true;
    final max = p.maxScrollExtent;
    if (max <= 0) return true;
    return max - pixels <= viewportHeight;
  }

  void _applyRange(_BlockVisibleRange range) {
    if (range.firstIndex == _firstIndex &&
        range.lastIndex == _lastIndex &&
        range.paddingTop == _paddingTop &&
        range.paddingBottom == _paddingBottom) {
      return;
    }
    setState(() {
      _firstIndex = range.firstIndex;
      _lastIndex = range.lastIndex;
      _paddingTop = range.paddingTop;
      _paddingBottom = range.paddingBottom;
    });
  }

  bool _scrolledNearEnd(double documentPixels) {
    if (!_scrollController.hasClients) return true;
    final max = _scrollController.position.maxScrollExtent;
    if (max <= 0) return true;
    return max - documentPixels <= _scrollController.position.viewportDimension;
  }

  void _onUnitMeasured(int index, double height) {
    if (!mounted || height <= 0) return;
    final before = _cache.heightOf(index);
    _cache.setMeasured(index, height);
    final delta = height - before;
    // In flatten mode the parent (turn/thread machinery) owns scroll
    // correction — height growth shifts the parent extent, not an inner panel.
    if (!widget.flatten && delta.abs() >= 0.5 && _scrollController.hasClients) {
      final unitStart = _cache.offsetBefore(_units.length, index);
      final scrollPixels = _scrollController.position.pixels;
      if (unitStart + before <= scrollPixels) {
        _pendingCorrection += delta;
        _scheduleCorrection();
      }
    }
    _syncVisibleRange();
  }

  void _scheduleCorrection() {
    if (_correctionScheduled) return;
    _correctionScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _correctionScheduled = false;
      final delta = _pendingCorrection;
      _pendingCorrection = 0;
      if (delta.abs() < 0.5 || !_scrollController.hasClients) return;
      final position = _scrollController.position;
      final target = (position.pixels + delta).clamp(
        0.0,
        position.maxScrollExtent,
      );
      if ((target - position.pixels).abs() >= 0.5) {
        position.jumpTo(target);
      }
    });
  }

  // --- Reveal (controller-driven block navigation) -------------------------

  static const Duration _revealDuration = Duration(milliseconds: 180);
  static const double _revealCorrectionThreshold = 2.0;

  Future<void> revealBlockPublic(int blockIndex) async {
    final unit = _unitForBlock(blockIndex);
    if (unit < 0 || !mounted) return;
    final epoch = ++_revealEpoch;
    // Initiate the reveal without awaiting its animation: the animation only
    // advances as frames are produced, so awaiting it here would deadlock
    // frame-driven callers/tests that reveal then settle.
    unawaited(_revealTo(unit).then((_) {
      if (!mounted) return;
      // Heights ahead may still be estimates; correct once they measure. The
      // pass is dropped when a newer reveal superseded this one.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || epoch != _revealEpoch) return;
        _revealCorrectionPass(unit);
      });
    }));
  }

  Future<void> _revealTo(int unit) async {
    final contentOffset = _cache.offsetBefore(_units.length, unit);
    if (!widget.flatten) {
      if (!_scrollController.hasClients ||
          !_scrollController.position.hasViewportDimension) {
        return;
      }
      await _animateTo(_scrollController.position, contentOffset);
      return;
    }
    final position = _parentPosition;
    final renderObject = context.findRenderObject();
    if (position == null || !position.hasViewportDimension) return;
    if (renderObject is! RenderBox || !renderObject.hasSize) return;
    final revealed = RenderAbstractViewport.of(renderObject)
        .getOffsetToReveal(renderObject, 0.0);
    await _animateTo(position, revealed.offset + contentOffset);
  }

  Future<void> _animateTo(ScrollPosition position, double contentOffset) async {
    final target = (contentOffset - position.viewportDimension * 0.25)
        .clamp(0.0, position.maxScrollExtent);
    if ((target - position.pixels).abs() < 1.0) return;
    await position.animateTo(
      target,
      duration: _revealDuration,
      curve: Curves.easeOutCubic,
    );
  }

  void _revealCorrectionPass(int unit) {
    final contentOffset = _cache.offsetBefore(_units.length, unit);
    if (!widget.flatten) {
      if (!_scrollController.hasClients) return;
      final position = _scrollController.position;
      final target =
          (contentOffset - position.viewportDimension * 0.25).clamp(0.0, position.maxScrollExtent);
      if ((target - position.pixels).abs() >= _revealCorrectionThreshold) {
        position.jumpTo(target);
      }
      return;
    }
    final position = _parentPosition;
    final renderObject = context.findRenderObject();
    if (position == null || renderObject is! RenderBox || !renderObject.hasSize) {
      return;
    }
    final revealed = RenderAbstractViewport.of(renderObject)
        .getOffsetToReveal(renderObject, 0.0);
    final target = (revealed.offset + contentOffset - position.viewportDimension * 0.25)
        .clamp(0.0, position.maxScrollExtent);
    if ((target - position.pixels).abs() >= _revealCorrectionThreshold) {
      position.jumpTo(target);
    }
  }

  // --- Build ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final resolvers = _resolversForBuild();
    final tokens = widget.tokens;
    final strings = widget.strings;
    final reg = widget.registry ?? BlockWidgetRegistry.builtIn();

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_units.isEmpty)
          const SizedBox.shrink()
        else if (_firstIndex > _lastIndex)
          // Cold first frame: estimated full extent so the scrollbar has a
          // stable range before units mount and measure.
          SizedBox(height: _cache.totalExtent(_units.length))
        else ...[
          SizedBox(height: _paddingTop),
          for (var i = _firstIndex; i <= _lastIndex; i++)
            _buildUnit(i, tokens, resolvers, strings, reg),
          SizedBox(height: _paddingBottom),
        ],
      ],
    );

    if (widget.flatten) {
      // Natural height inside the parent scroll — no inner scrollbar.
      return MarkdownStringsScope(strings: strings, child: content);
    }
    return MarkdownStringsScope(
      strings: strings,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: widget.maxHeight),
        child: SingleChildScrollView(
          controller: _scrollController,
          child: content,
        ),
      ),
    );
  }

  Widget _buildUnit(
    int i,
    MarkdownTokens tokens,
    MarkdownResolvers resolvers,
    MarkdownStrings strings,
    BlockWidgetRegistry reg,
  ) {
    final unit = _units[i];
    return _BlockMeasuredBox(
      key: ValueKey<int>(i),
      onMeasured: (h) => _onUnitMeasured(i, h),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (unit.gapBefore > 0) SizedBox(height: unit.gapBefore),
          _wrapHorizontal(unit.kind, unit.build(tokens, resolvers, strings, reg)),
        ],
      ),
    );
  }

  Widget _wrapHorizontal(MarkdownBlockKind kind, Widget child) {
    final m = widget.tokens.marginOf(kind);
    if (m.left == 0 && m.right == 0) return child;
    return Padding(
      padding: EdgeInsets.only(left: m.left, right: m.right),
      child: child,
    );
  }
}

/// One virtualized layout unit: a merged paragraph run or a single block, with
/// the inter-block gap folded in. Widgets are built lazily per visible unit.
class _MarkdownUnit {
  const _MarkdownUnit({
    required this.kind,
    required this.gapBefore,
    required this.build,
    this.firstBlockIndex = 0,
    this.lastBlockIndex = 0,
  });

  final MarkdownBlockKind kind;
  final double gapBefore;
  final Widget Function(
    MarkdownTokens,
    MarkdownResolvers,
    MarkdownStrings,
    BlockWidgetRegistry,
  ) build;

  /// Top-level block indexes covered (merged paragraph runs span several).
  final int firstBlockIndex;
  final int lastBlockIndex;
}

class _BlockVisibleRange {
  const _BlockVisibleRange({
    required this.firstIndex,
    required this.lastIndex,
    required this.paddingTop,
    required this.paddingBottom,
  });

  final int firstIndex;
  final int lastIndex;
  final double paddingTop;
  final double paddingBottom;
}

/// Variable-height index cache + visible-range math (ported from
/// ai_message_ui `TurnHeightCache`; keyed by unit index instead of turn id).
class _BlockHeightCache {
  _BlockHeightCache({required double estimate}) : _estimate = estimate;

  final double _estimate;
  final Map<int, double> _measured = {};

  double heightOf(int index) => _measured[index] ?? _estimate;

  bool isMeasured(int index) => _measured.containsKey(index);

  void setMeasured(int index, double height) {
    if (height <= 0) return;
    _measured[index] = height;
  }

  void invalidateAll() => _measured.clear();

  double totalExtent(int unitCount) {
    var sum = 0.0;
    for (var i = 0; i < unitCount; i++) {
      sum += heightOf(i);
    }
    return sum;
  }

  /// Cumulative height of units[0..index) (exclusive end).
  double offsetBefore(int unitCount, int index) {
    var sum = 0.0;
    final end = index.clamp(0, unitCount);
    for (var i = 0; i < end; i++) {
      sum += heightOf(i);
    }
    return sum;
  }

  _BlockVisibleRange visibleRange({
    required int unitCount,
    required double scrollPixels,
    required double viewportHeight,
    required int overscan,
  }) {
    if (unitCount == 0) {
      return const _BlockVisibleRange(
        firstIndex: 0,
        lastIndex: -1,
        paddingTop: 0,
        paddingBottom: 0,
      );
    }
    final top = scrollPixels < 0 ? 0.0 : scrollPixels;
    final bottom = top + viewportHeight;
    var acc = 0.0;
    var first = 0;
    var last = unitCount - 1;
    var foundFirst = false;
    for (var i = 0; i < unitCount; i++) {
      final h = heightOf(i);
      final unitBottom = acc + h;
      if (!foundFirst && unitBottom > top) {
        first = i;
        foundFirst = true;
      }
      if (acc < bottom) {
        last = i;
      }
      acc = unitBottom;
    }
    first = (first - overscan).clamp(0, unitCount - 1);
    last = (last + overscan).clamp(0, unitCount - 1);
    if (last < first) last = first;
    return _BlockVisibleRange(
      firstIndex: first,
      lastIndex: last,
      paddingTop: offsetBefore(unitCount, first),
      paddingBottom:
          totalExtent(unitCount) - offsetBefore(unitCount, last + 1),
    );
  }

  /// Shrinks [range] so at most [maxUnmeasured] units lack a measured height.
  ///
  /// From the focus edge ([preferEnd] → suffix, else prefix), keep measured
  /// units and admit unmeasured ones up to the cap — avoids a cold-mount burst
  /// when estimates are far from real heights.
  _BlockVisibleRange clampUnmeasuredMounts({
    required int unitCount,
    required _BlockVisibleRange range,
    required int maxUnmeasured,
    required bool preferEnd,
  }) {
    if (range.lastIndex < range.firstIndex) return range;
    final limit = maxUnmeasured < 1 ? 1 : maxUnmeasured;

    var unmeasured = 0;
    for (var i = range.firstIndex; i <= range.lastIndex; i++) {
      if (!isMeasured(i)) unmeasured++;
    }
    if (unmeasured <= limit) return range;

    final int first;
    final int last;
    if (preferEnd) {
      last = range.lastIndex;
      var start = last;
      var keptUnmeasured = 0;
      for (var i = range.lastIndex; i >= range.firstIndex; i--) {
        if (!isMeasured(i)) {
          if (keptUnmeasured >= limit) break;
          keptUnmeasured++;
        }
        start = i;
      }
      first = start;
    } else {
      first = range.firstIndex;
      var end = first;
      var keptUnmeasured = 0;
      for (var i = range.firstIndex; i <= range.lastIndex; i++) {
        if (!isMeasured(i)) {
          if (keptUnmeasured >= limit) break;
          keptUnmeasured++;
        }
        end = i;
      }
      last = end;
    }

    return _BlockVisibleRange(
      firstIndex: first,
      lastIndex: last,
      paddingTop: offsetBefore(unitCount, first),
      paddingBottom:
          totalExtent(unitCount) - offsetBefore(unitCount, last + 1),
    );
  }
}

/// Measures a mounted unit post-frame and reports its height (ported from
/// ai_message_ui `_MeasuredBox`).
class _BlockMeasuredBox extends StatefulWidget {
  const _BlockMeasuredBox({
    required this.onMeasured,
    required this.child,
    super.key,
  });

  final ValueChanged<double> onMeasured;
  final Widget child;

  @override
  State<_BlockMeasuredBox> createState() => _BlockMeasuredBoxState();
}

class _BlockMeasuredBoxState extends State<_BlockMeasuredBox> {
  final GlobalKey _key = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _measure();
    });
  }

  @override
  void didUpdateWidget(covariant _BlockMeasuredBox oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _measure();
    });
  }

  void _measure() {
    if (!mounted) return;
    final box = _key.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    widget.onMeasured(box.size.height);
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<SizeChangedLayoutNotification>(
      onNotification: (_) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _measure();
        });
        return true;
      },
      child: SizeChangedLayoutNotifier(
        child: KeyedSubtree(key: _key, child: widget.child),
      ),
    );
  }
}
