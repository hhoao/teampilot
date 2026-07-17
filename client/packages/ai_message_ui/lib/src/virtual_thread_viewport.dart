import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter/widgets.dart';

import 'thread_turns.dart';
import 'turn_height_cache.dart';

class VirtualThreadViewport extends StatefulWidget {
  const VirtualThreadViewport({
    required this.messages,
    required this.scrollController,
    required this.messageBuilder,
    this.header,
    this.overscan = 3,
    this.estimateHeight = 200,
    /// When true, measurement must not request scroll corrections upward.
    this.suppressMeasureScrollCorrection = false,
    this.onMeasureScrollCorrection,
    super.key,
  });

  final List<AiMessage> messages;
  final ScrollController scrollController;
  final Widget Function(BuildContext context, AiMessage message) messageBuilder;
  final Widget? header;
  final int overscan;
  final double estimateHeight;
  final bool suppressMeasureScrollCorrection;

  /// Optional: host applies pixel delta after height cache changes (load-older
  /// / expand). Must be called post-frame — never from a scroll listener body
  /// that re-enters via jumpTo.
  final void Function(double deltaPixels)? onMeasureScrollCorrection;

  @override
  State<VirtualThreadViewport> createState() => _VirtualThreadViewportState();
}

class _VirtualThreadViewportState extends State<VirtualThreadViewport> {
  late List<ThreadTurn> _turns;
  late TurnHeightCache _cache;
  final Map<String, String> _identityByTurnId = {};
  late Map<String, AiMessage> _messageById;

  int _firstIndex = 0;
  int _lastIndex = -1;
  double _paddingTop = 0;
  double _paddingBottom = 0;

  bool _correctionScheduled = false;
  double _pendingCorrection = 0;

  @override
  void initState() {
    super.initState();
    _cache = TurnHeightCache(estimate: widget.estimateHeight);
    _rebuildTurns(previous: const []);
    _syncVisibleRange();
    widget.scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _syncVisibleRange();
    });
  }

  @override
  void didUpdateWidget(covariant VirtualThreadViewport oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scrollController != widget.scrollController) {
      oldWidget.scrollController.removeListener(_onScroll);
      widget.scrollController.addListener(_onScroll);
    }
    if (oldWidget.estimateHeight != widget.estimateHeight) {
      _cache = TurnHeightCache(estimate: widget.estimateHeight);
    }
    if (!identical(oldWidget.messages, widget.messages)) {
      _rebuildTurns(previous: _turns);
    }
    _syncVisibleRange();
  }

  @override
  void dispose() {
    widget.scrollController.removeListener(_onScroll);
    super.dispose();
  }

  void _rebuildTurns({required List<ThreadTurn> previous}) {
    _turns = reuseTurnsIfSameMembership(
      previous: previous,
      messages: widget.messages,
    );
    _messageById = {for (final m in widget.messages) m.id: m};
    final liveIds = <String>{};
    for (final turn in _turns) {
      liveIds.add(turn.id);
      final identity = turnContentIdentity(turn, widget.messages);
      final previousIdentity = _identityByTurnId[turn.id];
      if (previousIdentity != null && previousIdentity != identity) {
        _cache.invalidate(turn.id);
      }
      _identityByTurnId[turn.id] = identity;
    }
    _identityByTurnId.removeWhere((id, _) => !liveIds.contains(id));
  }

  void _onScroll() {
    // Never jumpTo here — only remount when the visible window changes.
    _syncVisibleRange();
  }

  void _syncVisibleRange() {
    final TurnVisibleRange range;
    final controller = widget.scrollController;
    // hasClients can be true before the first layout sets viewportDimension.
    if (controller.hasClients &&
        controller.position.hasViewportDimension) {
      final position = controller.position;
      range = _cache.visibleRange(
        turns: _turns,
        scrollPixels: position.pixels,
        viewportHeight: position.viewportDimension,
        overscan: widget.overscan,
      );
    } else if (_turns.isEmpty) {
      range = const TurnVisibleRange(
        firstIndex: 0,
        lastIndex: -1,
        paddingTop: 0,
        paddingBottom: 0,
      );
    } else {
      // Small prefix until first layout can measure.
      final count = (widget.overscan * 2 + 1).clamp(1, _turns.length);
      final last = count - 1;
      range = TurnVisibleRange(
        firstIndex: 0,
        lastIndex: last,
        paddingTop: 0,
        paddingBottom:
            _cache.totalExtent(_turns) - _cache.offsetBefore(_turns, last + 1),
      );
    }

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

  void _onTurnMeasured(String turnId, double height) {
    if (height <= 0) return;
    final before = _cache.heightOf(turnId);
    _cache.setMeasured(turnId, height);
    final after = _cache.heightOf(turnId);
    final delta = after - before;

    if (delta.abs() >= 0.5) {
      final turnIndex = _turns.indexWhere((t) => t.id == turnId);
      if (turnIndex >= 0) {
        // Start of this turn (heights of turns before it); own height excluded.
        final turnStart = _cache.offsetBefore(_turns, turnIndex);
        final scrollPixels = widget.scrollController.hasClients
            ? widget.scrollController.position.pixels
            : 0.0;
        if (!widget.suppressMeasureScrollCorrection &&
            turnStart < scrollPixels &&
            widget.onMeasureScrollCorrection != null) {
          _pendingCorrection += delta;
          _scheduleCorrection();
        }
      }
    }

    _syncVisibleRange();
  }

  void _scheduleCorrection() {
    if (_correctionScheduled) return;
    _correctionScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _correctionScheduled = false;
      final delta = _pendingCorrection;
      _pendingCorrection = 0;
      if (delta.abs() < 0.5) return;
      if (widget.suppressMeasureScrollCorrection) return;
      widget.onMeasureScrollCorrection?.call(delta);
    });
  }

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[
      if (widget.header != null) widget.header!,
      SizedBox(height: _paddingTop),
    ];

    if (_lastIndex >= _firstIndex && _turns.isNotEmpty) {
      for (var i = _firstIndex; i <= _lastIndex; i++) {
        final turn = _turns[i];
        children.add(
          _MeasuredTurn(
            key: ValueKey(turn.id),
            turnId: turn.id,
            onMeasured: _onTurnMeasured,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final id in turn.messageIds)
                  if (_messageById[id] case final message?)
                    widget.messageBuilder(context, message),
              ],
            ),
          ),
        );
      }
    }

    children.add(SizedBox(height: _paddingBottom));

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }
}

class _MeasuredTurn extends StatefulWidget {
  const _MeasuredTurn({
    required this.turnId,
    required this.onMeasured,
    required this.child,
    super.key,
  });

  final String turnId;
  final void Function(String turnId, double height) onMeasured;
  final Widget child;

  @override
  State<_MeasuredTurn> createState() => _MeasuredTurnState();
}

class _MeasuredTurnState extends State<_MeasuredTurn> {
  final GlobalKey _key = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
  }

  @override
  void didUpdateWidget(covariant _MeasuredTurn oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
  }

  void _measure() {
    final box = _key.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    widget.onMeasured(widget.turnId, box.size.height);
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<SizeChangedLayoutNotification>(
      onNotification: (_) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
        return true;
      },
      child: SizeChangedLayoutNotifier(
        child: KeyedSubtree(key: _key, child: widget.child),
      ),
    );
  }
}
