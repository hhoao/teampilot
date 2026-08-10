import 'dart:async';

import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter/widgets.dart';

import 'frozen_size.dart';
import 'thread_turns.dart';
import 'turn_height_cache.dart';
import 'turn_mount_keep_alive.dart';

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
    /// History opens stick-to-end: cold / estimate windows prefer the suffix.
    this.anchorEnd = false,
    /// When false, only spacers (estimated extent) — no message widgets.
    /// Hosts set true after the first jump-to-end so open does not build the
    /// wrong end of the thread under [SingleChildScrollView].
    this.mountTurns = true,
    /// How long recently scrolled-off turns keep their Element in an offstage
    /// freeze cache (Claude DOM-like). [Duration.zero] disables.
    this.keepAliveDuration = Duration.zero,
    /// Cap on offstage cached turns (does not widen the scroll Column).
    this.keepAliveMaxExtra = 12,
    /// Never shrink the mounted index range (Claude-like residency while scrolling).
    this.retainMountedTurns = false,
    /// After the first mount window, grow in chunks until every turn in
    /// [messages] is mounted (pagination already bounds the data window).
    this.fillDataWindow = false,
    /// Injectable clock (tests); defaults to [DateTime.now].
    this.clock,
    /// When [revealEpoch] changes and [revealMessageId] is non-null and present
    /// in [messages], compute the pixel offset of its turn and call
    /// [onRevealOffset] post-frame (estimate-based until that turn is measured).
    /// Host jumps the scroll controller; the normal measurement-correction path
    /// then refines.
    this.revealMessageId,
    this.revealEpoch = 0,
    this.onRevealOffset,
    this.buildKey,
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

  final bool anchorEnd;
  final bool mountTurns;
  final Duration keepAliveDuration;
  final int keepAliveMaxExtra;
  final bool retainMountedTurns;
  final bool fillDataWindow;
  final DateTime Function()? clock;

  /// See constructor docs.
  final String? revealMessageId;
  final int revealEpoch;
  /// Delivered in viewport-space document pixels (header height included). The
  /// host must add its own outer scroll padding (e.g. SingleChildScrollView top
  /// padding) when jumping.
  final void Function(double offset)? onRevealOffset;

  /// Host-controlled cache key. When it changes (with the same message list
  /// instance), cached `messageBuilder` outputs are invalidated so the builder
  /// re-runs — needed when the host's builder depends on external state such as
  /// a highlight id.
  final Object? buildKey;

  @override
  State<VirtualThreadViewport> createState() => _VirtualThreadViewportState();
}

class _VirtualThreadViewportState extends State<VirtualThreadViewport> {
  late List<ThreadTurn> _turns;
  late TurnHeightCache _cache;
  final Map<String, String> _identityByTurnId = {};
  Map<String, AiMessage> _messageById = const {};

  int _firstIndex = 0;
  int _lastIndex = -1;
  double _paddingTop = 0;
  double _paddingBottom = 0;
  double _headerHeight = 0;

  bool _correctionScheduled = false;
  double _pendingCorrection = 0;

  final Map<String, DateTime> _keepAliveUntil = {};
  List<String> _offstageIds = const [];
  final Map<String, GlobalKey> _turnKeys = {};
  /// Cached message column per turn — identical [Widget] instances skip Element
  /// rebuild when softReload only changes another turn's content.
  final Map<String, _CachedTurnBody> _builtTurnBody = {};
  Timer? _keepAliveTimer;
  var _fillScheduled = false;

  String? _lastRevealMessageId;
  int _lastRevealEpoch = 0;

  static const _fillChunk = 2;

  @override
  void initState() {
    super.initState();
    // Seed the last-seen reveal so the first build (which carries the host's
    // initial request) does not re-fire on the very first frame.
    _lastRevealMessageId = widget.revealMessageId;
    _lastRevealEpoch = widget.revealEpoch;
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
    if (widget.header == null) {
      _headerHeight = 0;
    }
    if (!identical(oldWidget.messages, widget.messages)) {
      final previousTurns = _turns;
      final prevFirst = _firstIndex;
      final prevLast = _lastIndex;
      _rebuildTurns(previous: previousTurns);
      if ((widget.retainMountedTurns || widget.fillDataWindow) &&
          prevLast >= prevFirst &&
          previousTurns.isNotEmpty) {
        _remapRetainWindow(
          previousTurns: previousTurns,
          prevFirst: prevFirst,
          prevLast: prevLast,
        );
      } else if (widget.retainMountedTurns || widget.fillDataWindow) {
        _firstIndex = 0;
        _lastIndex = -1;
        _fillScheduled = false;
      }
    }
    _syncVisibleRange();
    if (widget.revealMessageId != _lastRevealMessageId ||
        widget.revealEpoch != _lastRevealEpoch) {
      _lastRevealMessageId = widget.revealMessageId;
      _lastRevealEpoch = widget.revealEpoch;
      final targetId = widget.revealMessageId;
      final onOffset = widget.onRevealOffset;
      if (targetId != null && onOffset != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          final turnIndex =
              _turns.indexWhere((t) => t.messageIds.contains(targetId));
          if (turnIndex < 0) return;
          onOffset(_headerHeight + _cache.offsetBefore(_turns, turnIndex));
        });
      }
    }
  }

  @override
  void dispose() {
    _keepAliveTimer?.cancel();
    widget.scrollController.removeListener(_onScroll);
    super.dispose();
  }

  void _rebuildTurns({required List<ThreadTurn> previous}) {
    _turns = reuseTurnsIfSameMembership(
      previous: previous,
      messages: widget.messages,
    );
    // Host builders often close over tip/lastId chrome. Membership changes
    // (append/prepend) can restyle neighbors without changing message content.
    if (!identical(_turns, previous)) {
      _builtTurnBody.clear();
    }
    // Snapshot the previous message map BEFORE overwriting _messageById so we
    // can detect which message objects changed (reference-comparison — AiMessage
    // is immutable, so a new object for the same id means content changed).
    final prevMessagesById = _messageById;
    _messageById = {for (final m in widget.messages) m.id: m};
    final liveIds = <String>{};
    // Build a quick lookup of previous turns by id so we can skip identity
    // recomputation for turns that are unchanged (identical object + unchanged
    // message references + not the streaming tip).
    final prevById = <String, ThreadTurn>{
      for (final t in previous) t.id: t,
    };
    final tipId = _turns.isNotEmpty ? _turns.last.id : null;
    for (final turn in _turns) {
      liveIds.add(turn.id);
      final prev = prevById[turn.id];
      // Unchanged turn object with all messages still the same objects: skip the
      // O(messages-in-turn) identity recomputation. Always recompute the tip
      // turn — streaming appends/edits create new message objects for the same
      // IDs. Also fall through to recompute when any message reference changed
      // (content edits replace the AiMessage object for a given id).
      if (identical(turn, prev) && turn.id != tipId) {
        var allMessagesSame = true;
        for (final id in turn.messageIds) {
          if (!identical(_messageById[id], prevMessagesById[id])) {
            allMessagesSame = false;
            break;
          }
        }
        if (allMessagesSame) continue;
      }
      final identity = turnContentIdentity(turn, widget.messages);
      final previousIdentity = _identityByTurnId[turn.id];
      if (previousIdentity != null && previousIdentity != identity) {
        _cache.invalidate(turn.id);
      }
      _identityByTurnId[turn.id] = identity;
    }
    _identityByTurnId.removeWhere((id, _) => !liveIds.contains(id));
    _keepAliveUntil.removeWhere((id, _) => !liveIds.contains(id));
    _turnKeys.removeWhere((id, _) => !liveIds.contains(id));
    _builtTurnBody.removeWhere((id, _) => !liveIds.contains(id));
  }

  void _onScroll() {
    // Never jumpTo here — only remount when the visible window changes.
    _syncVisibleRange();
  }

  /// Scroll offset in turn-space (turns start after the optional header).
  double _scrollPixelsInTurnSpace(double documentPixels) {
    final inTurn = documentPixels - _headerHeight;
    return inTurn < 0 ? 0.0 : inTurn;
  }

  void _onHeaderMeasured(double height) {
    if (!mounted) return;
    if (height <= 0) {
      if (_headerHeight == 0) return;
      _headerHeight = 0;
      _syncVisibleRange();
      return;
    }
    if ((height - _headerHeight).abs() < 0.5) return;
    _headerHeight = height;
    _syncVisibleRange();
  }

  Set<String> _idealIds(TurnVisibleRange range) {
    if (range.lastIndex < range.firstIndex || _turns.isEmpty) {
      return {};
    }
    final ids = <String>{};
    for (var i = range.firstIndex; i <= range.lastIndex; i++) {
      ids.add(_turns[i].id);
    }
    return ids;
  }

  void _syncVisibleRange() {
    if (!mounted) return;
    TurnVisibleRange range;
    final controller = widget.scrollController;
    var offstageChanged = false;

    if (!widget.mountTurns) {
      // Estimated full extent only — lets the host jumpTo end before mounting.
      _keepAliveUntil.clear();
      _offstageIds = const [];
      _keepAliveTimer?.cancel();
      _keepAliveTimer = null;
      range = TurnVisibleRange(
        firstIndex: 0,
        lastIndex: -1,
        paddingTop: 0,
        paddingBottom: _cache.totalExtent(_turns),
      );
      offstageChanged = true;
    } else if (controller.hasClients &&
        controller.position.hasViewportDimension) {
      final position = controller.position;
      var scrollPixels = position.pixels;
      // Only while stick-to-end: first layout may still be at 0 while we intend
      // the bottom. Do NOT remap pixels<=1 after the user scrolls to the top —
      // that mounts the suffix under a huge paddingTop and paints a blank frame.
      final stickToEnd = widget.suppressMeasureScrollCorrection;
      if (stickToEnd &&
          widget.anchorEnd &&
          position.maxScrollExtent > 0 &&
          scrollPixels <= 1.0) {
        scrollPixels = position.maxScrollExtent;
      }
      range = _cache.clampUnmeasuredMounts(
        turns: _turns,
        range: _cache.visibleRange(
          turns: _turns,
          scrollPixels: _scrollPixelsInTurnSpace(scrollPixels),
          viewportHeight: position.viewportDimension,
          overscan: widget.overscan,
        ),
        maxUnmeasured: _coldMountLimit,
        preferEnd: stickToEnd || _scrolledNearEnd(scrollPixels),
      );
      if (widget.retainMountedTurns) {
        range = _retainUnion(range);
      }
      // Offstage TTL is redundant when we retain/fill the data window.
      if (!widget.retainMountedTurns && !widget.fillDataWindow) {
        offstageChanged = _syncOffstageCache(range);
      } else if (_offstageIds.isNotEmpty || _keepAliveUntil.isNotEmpty) {
        _keepAliveUntil.clear();
        _offstageIds = const [];
        _keepAliveTimer?.cancel();
        _keepAliveTimer = null;
        offstageChanged = true;
      }
      if (widget.fillDataWindow) {
        _scheduleFillDataWindow();
      }
    } else if (_turns.isEmpty) {
      range = const TurnVisibleRange(
        firstIndex: 0,
        lastIndex: -1,
        paddingTop: 0,
        paddingBottom: 0,
      );
    } else {
      // Until first layout: mount a small window at the anchored end.
      final count = _coldMountLimit.clamp(1, _turns.length);
      if (widget.anchorEnd) {
        final first = _turns.length - count;
        range = TurnVisibleRange(
          firstIndex: first,
          lastIndex: _turns.length - 1,
          paddingTop: _cache.offsetBefore(_turns, first),
          paddingBottom: 0,
        );
      } else {
        final last = count - 1;
        range = TurnVisibleRange(
          firstIndex: 0,
          lastIndex: last,
          paddingTop: 0,
          paddingBottom: _cache.totalExtent(_turns) -
              _cache.offsetBefore(_turns, last + 1),
        );
      }
    }

    final rangeChanged = range.firstIndex != _firstIndex ||
        range.lastIndex != _lastIndex ||
        range.paddingTop != _paddingTop ||
        range.paddingBottom != _paddingBottom;
    if (!rangeChanged && !offstageChanged) return;

    setState(() {
      _firstIndex = range.firstIndex;
      _lastIndex = range.lastIndex;
      _paddingTop = range.paddingTop;
      _paddingBottom = range.paddingBottom;
    });
  }

  DateTime get _now => widget.clock?.call() ?? DateTime.now();

  /// Keep already-mounted turns pinned across list membership changes (e.g.
  /// load-older prepend) by remapping turn ids to the new index range.
  void _remapRetainWindow({
    required List<ThreadTurn> previousTurns,
    required int prevFirst,
    required int prevLast,
  }) {
    final pinnedIds = <String>{};
    for (var i = prevFirst; i <= prevLast; i++) {
      if (i >= 0 && i < previousTurns.length) {
        pinnedIds.add(previousTurns[i].id);
      }
    }
    if (pinnedIds.isEmpty || _turns.isEmpty) {
      _firstIndex = 0;
      _lastIndex = -1;
      _fillScheduled = false;
      return;
    }

    var first = _turns.length;
    var last = -1;
    for (var i = 0; i < _turns.length; i++) {
      if (!pinnedIds.contains(_turns[i].id)) continue;
      if (i < first) first = i;
      if (i > last) last = i;
    }
    if (last < first) {
      _firstIndex = 0;
      _lastIndex = -1;
    } else {
      _firstIndex = first;
      _lastIndex = last;
      _paddingTop = _cache.offsetBefore(_turns, first);
      _paddingBottom = _cache.totalExtent(_turns) -
          _cache.offsetBefore(_turns, last + 1);
    }
    // Allow fill to grow into newly prepended turns only.
    _fillScheduled = false;
  }

  TurnVisibleRange _retainUnion(TurnVisibleRange ideal) {
    if (_lastIndex < _firstIndex || _turns.isEmpty) return ideal;
    final first = ideal.firstIndex < _firstIndex ? ideal.firstIndex : _firstIndex;
    final last = ideal.lastIndex > _lastIndex ? ideal.lastIndex : _lastIndex;
    return TurnVisibleRange(
      firstIndex: first,
      lastIndex: last,
      paddingTop: _cache.offsetBefore(_turns, first),
      paddingBottom:
          _cache.totalExtent(_turns) - _cache.offsetBefore(_turns, last + 1),
    );
  }

  void _scheduleFillDataWindow() {
    if (!widget.fillDataWindow || !widget.mountTurns) return;
    if (_turns.isEmpty) return;
    if (_lastIndex >= _firstIndex &&
        _firstIndex <= 0 &&
        _lastIndex >= _turns.length - 1) {
      return;
    }
    if (_fillScheduled) return;
    _fillScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fillScheduled = false;
      if (!mounted || !widget.fillDataWindow || !widget.mountTurns) return;
      if (_turns.isEmpty) return;

      var first = _firstIndex;
      var last = _lastIndex;
      if (last < first) {
        // Seed from current pin emptiness — sync will have set a cold window.
        return;
      }
      final beforeFirst = first;
      final beforeLast = last;
      // One edge per frame keeps fill spikes smaller (test62).
      if (first > 0) {
        first = (first - _fillChunk).clamp(0, first);
      } else if (last < _turns.length - 1) {
        last = (last + _fillChunk).clamp(last, _turns.length - 1);
      }
      if (first == beforeFirst && last == beforeLast) return;

      setState(() {
        _firstIndex = first;
        _lastIndex = last;
        _paddingTop = _cache.offsetBefore(_turns, first);
        _paddingBottom = _cache.totalExtent(_turns) -
            _cache.offsetBefore(_turns, last + 1);
      });
      if (first > 0 || last < _turns.length - 1) {
        _scheduleFillDataWindow();
      }
    });
  }

  /// Parks departed turns in an offstage freeze cache; does not widen [ideal].
  bool _syncOffstageCache(TurnVisibleRange ideal) {
    final previousIdeal = _idealIds(
      TurnVisibleRange(
        firstIndex: _firstIndex,
        lastIndex: _lastIndex,
        paddingTop: _paddingTop,
        paddingBottom: _paddingBottom,
      ),
    );
    final now = _now;
    final result = syncOffstageTurnCache(
      turns: _turns,
      idealIds: _idealIds(ideal),
      previousIdealIds: previousIdeal,
      keepAliveUntil: _keepAliveUntil,
      now: now,
      ttl: widget.keepAliveDuration,
      maxCached: widget.keepAliveMaxExtra,
    );
    _scheduleKeepAliveTick(result.nextExpiry, now);
    final idsChanged = result.offstageIds.length != _offstageIds.length ||
        !_listEquals(result.offstageIds, _offstageIds);
    if (idsChanged) {
      // Drop keys for fully evicted turns so Elements dispose.
      final live = {..._idealIds(ideal), ...result.offstageIds};
      _turnKeys.removeWhere((id, _) => !live.contains(id));
      _offstageIds = result.offstageIds;
    }
    return result.changed || idsChanged;
  }

  bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  void _scheduleKeepAliveTick(DateTime? nextExpiry, DateTime now) {
    _keepAliveTimer?.cancel();
    _keepAliveTimer = null;
    if (nextExpiry == null) return;
    final delay = nextExpiry.difference(now);
    if (delay <= Duration.zero) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _syncVisibleRange();
      });
      return;
    }
    _keepAliveTimer = Timer(delay, () {
      if (!mounted) return;
      _syncVisibleRange();
    });
  }

  /// Max turns mounted while heights are still estimates.
  int get _coldMountLimit => (widget.overscan < 1 ? 1 : widget.overscan);

  bool _scrolledNearEnd(double documentPixels) {
    final controller = widget.scrollController;
    if (!controller.hasClients) return widget.anchorEnd;
    final max = controller.position.maxScrollExtent;
    if (max <= 0) return widget.anchorEnd;
    return max - documentPixels <= controller.position.viewportDimension;
  }

  void _onTurnMeasured(String turnId, double height) {
    if (!mounted) return;
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
        final scrollInTurn = widget.scrollController.hasClients
            ? _scrollPixelsInTurnSpace(
                widget.scrollController.position.pixels,
              )
            : 0.0;
        // Only correct when the turn was fully above the viewport top.
        final fullyAbove = turnStart + before <= scrollInTurn;
        if (!widget.suppressMeasureScrollCorrection &&
            fullyAbove &&
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
      if (!mounted) return;
      _correctionScheduled = false;
      final delta = _pendingCorrection;
      _pendingCorrection = 0;
      if (delta.abs() < 0.5) return;
      if (widget.suppressMeasureScrollCorrection) return;
      widget.onMeasureScrollCorrection?.call(delta);
    });
  }

  GlobalKey _keyFor(String turnId) =>
      _turnKeys.putIfAbsent(turnId, GlobalKey.new);

  Widget _turnBody(ThreadTurn turn) {
    final highlightInTurn =
        widget.buildKey != null && turn.messageIds.contains(widget.buildKey);
    final identity = Object.hash(
      _identityByTurnId[turn.id] ?? turnContentIdentity(turn, widget.messages),
      highlightInTurn ? widget.buildKey : null,
    );
    final cached = _builtTurnBody[turn.id];
    if (cached != null && cached.identity == identity) {
      return cached.child;
    }
    final child = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final id in turn.messageIds)
          if (_messageById[id] case final message?)
            widget.messageBuilder(context, message),
      ],
    );
    _builtTurnBody[turn.id] = _CachedTurnBody(identity: identity, child: child);
    return child;
  }

  Widget _buildTurn({required ThreadTurn turn, required bool frozen}) {
    final height = _cache.isMeasured(turn.id)
        ? _cache.heightOf(turn.id)
        : widget.estimateHeight;
    return FrozenSize(
      key: _keyFor(turn.id),
      frozen: frozen,
      frozenHeight: height,
      child: _MeasuredBox(
        onMeasured: frozen ? (_) {} : (h) => _onTurnMeasured(turn.id, h),
        child: _turnBody(turn),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final idealIds = <String>{};
    if (_lastIndex >= _firstIndex && _turns.isNotEmpty) {
      for (var i = _firstIndex; i <= _lastIndex; i++) {
        idealIds.add(_turns[i].id);
      }
    }

    final offstageTurns = <ThreadTurn>[];
    for (final id in _offstageIds) {
      if (idealIds.contains(id)) continue;
      final idx = _turns.indexWhere((t) => t.id == id);
      if (idx >= 0) offstageTurns.add(_turns[idx]);
    }

    final children = <Widget>[
      if (widget.header != null)
        _MeasuredBox(
          onMeasured: _onHeaderMeasured,
          child: widget.header!,
        ),
      if (offstageTurns.isNotEmpty)
        Offstage(
          offstage: true,
          child: TickerMode(
            enabled: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final turn in offstageTurns)
                  _buildTurn(turn: turn, frozen: true),
              ],
            ),
          ),
        ),
      SizedBox(height: _paddingTop),
    ];

    if (_lastIndex >= _firstIndex && _turns.isNotEmpty) {
      for (var i = _firstIndex; i <= _lastIndex; i++) {
        children.add(_buildTurn(turn: _turns[i], frozen: false));
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

class _CachedTurnBody {
  const _CachedTurnBody({required this.identity, required this.child});

  final Object identity;
  final Widget child;
}

class _MeasuredBox extends StatefulWidget {
  const _MeasuredBox({
    required this.onMeasured,
    required this.child,
  });

  final void Function(double height) onMeasured;
  final Widget child;

  @override
  State<_MeasuredBox> createState() => _MeasuredBoxState();
}

class _MeasuredBoxState extends State<_MeasuredBox> {
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
  void didUpdateWidget(covariant _MeasuredBox oldWidget) {
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
