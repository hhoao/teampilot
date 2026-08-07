import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../ir/markdown_block_kind.dart';
import '../ir/markdown_document.dart';
import '../registry/block_widget_registry.dart';
import '../registry/markdown_resolvers.dart';
import '../strings.dart';
import '../tokens/markdown_tokens.dart';
import 'inline_spans.dart';

/// Bounded, internally-scrolling, block-level virtualized markdown renderer.
///
/// [MarkdownView] lays out every block in a [Column], which freezes the frame
/// for a single very large message (e.g. a bundled-skill user turn). This view
/// instead keeps a height cache per layout unit (a merged paragraph run or a
/// single block) and mounts only the units inside the scroll viewport (+
/// overscan), recycling on scroll — Monaco-style smooth browsing of a huge
/// message. Renders the same blocks as [MarkdownView] (registry + tokens +
/// gaps), just lazily.
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
  });

  final MarkdownDocument document;
  final MarkdownTokens tokens;
  final MarkdownResolvers resolvers;
  final MarkdownStrings strings;
  final BlockWidgetRegistry? registry;

  /// Cap on the internal scroll viewport (the panel height).
  final double maxHeight;

  /// Per-unit height used before a unit has been measured.
  final double estimateHeight;

  /// Extra units mounted beyond the visible range.
  final int overscan;

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

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _cache = _BlockHeightCache(estimate: widget.estimateHeight);
    _units = _computeUnits(widget.document);
    _scrollController.addListener(_onScroll);
    _syncVisibleRange();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _syncVisibleRange();
    });
  }

  @override
  void didUpdateWidget(covariant VirtualMarkdownView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.document != widget.document) {
      _units = _computeUnits(widget.document);
      _cache.invalidateAll();
      _firstIndex = 0;
      _lastIndex = -1;
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(0);
      }
      _syncVisibleRange();
    }
  }

  @override
  void dispose() {
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
        units.add(
          _MarkdownUnit(
            kind: MarkdownBlockKind.paragraph,
            gapBefore: _gapBefore(previous?.kind, MarkdownBlockKind.paragraph),
            build: (tokens, resolvers, strings, reg) => run.length == 1
                ? buildParagraph(run.first, tokens, resolvers)
                : buildMergedParagraphs(run, tokens, resolvers),
          ),
        );
        previous = run.last;
        i = end;
        continue;
      }

      units.add(
        _MarkdownUnit(
          kind: block.kind,
          gapBefore: _gapBefore(previous?.kind, block.kind),
          build: (tokens, resolvers, strings, reg) =>
              reg.build(block, tokens, resolvers, strings),
        ),
      );
      previous = block;
      i++;
    }
    return units;
  }

  double _gapBefore(MarkdownBlockKind? previous, MarkdownBlockKind next) =>
      previous == null ? 0 : gapBetween(previous, next, widget.tokens);

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
    if (delta.abs() >= 0.5 && _scrollController.hasClients) {
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

  // --- Build ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final resolvers = _resolversForBuild();
    final tokens = widget.tokens;
    final strings = widget.strings;
    final reg = widget.registry ?? BlockWidgetRegistry.builtIn();

    return MarkdownStringsScope(
      strings: strings,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: widget.maxHeight),
        child: SingleChildScrollView(
          controller: _scrollController,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_units.isEmpty)
                const SizedBox.shrink()
              else if (_firstIndex > _lastIndex)
                // Cold first frame: estimated full extent so the scrollbar has
                // a stable range before units mount and measure.
                SizedBox(height: _cache.totalExtent(_units.length))
              else ...[
                SizedBox(height: _paddingTop),
                for (var i = _firstIndex; i <= _lastIndex; i++)
                  _buildUnit(i, tokens, resolvers, strings, reg),
                SizedBox(height: _paddingBottom),
              ],
            ],
          ),
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
  });

  final MarkdownBlockKind kind;
  final double gapBefore;
  final Widget Function(
    MarkdownTokens,
    MarkdownResolvers,
    MarkdownStrings,
    BlockWidgetRegistry,
  ) build;
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
