import 'dart:async';
import 'dart:collection';

import '../../utils/logging/logger.dart';
import 'dispatcher.dart';

/// YARN AsyncDispatcher port: unbounded queue + single consume loop +
/// per-family routing with multicast.
///
/// Correspondence to org.apache.hadoop.yarn.event.AsyncDispatcher:
/// - [dispatch] is `getEventHandler().handle()` — enqueue-only, never blocks;
/// - a single consume loop delivers events in global FIFO order (YARN's
///   single consumer thread over a `LinkedBlockingQueue`);
/// - [registerFamily] appends to the family's handler list, so multiple
///   handlers per family are all invoked (YARN wraps them in a
///   MultiListenerHandler);
/// - [unregister] removes the handler from every family;
/// - [stop] drains everything already queued before closing.
///
/// Deviations from YARN (deliberate, see the design spec):
/// - a throwing handler is logged and skipped; the remaining handlers for
///   the event and all subsequent events still run (YARN lets the exception
///   kill the dispatch thread / process);
/// - the queue is unbounded, with a depth warning once it exceeds
///   [warnDepth] (YARN uses a bounded blocking queue because producers are
///   multi-threaded; in a single isolate, blocking dispatch would deadlock);
/// - the idle consume loop parks on a completer instead of polling (YARN
///   threads block on the queue's `take()`).
class AsyncDispatcher implements Dispatcher {
  AsyncDispatcher({
    int warnDepth = 1000,
    void Function(int depth)? onWarn,
    AppLogger? logger,
  }) : _warnDepth = warnDepth,
       _onWarn = onWarn,
       _logger = logger ?? appLogger;

  static const _tag = 'event-dispatcher';

  final int _warnDepth;
  final void Function(int depth)? _onWarn;
  final AppLogger _logger;
  final Queue<DispatcherEvent<dynamic>> _queue = Queue();
  // Key: the family's kind enum Type (matches event.kind.runtimeType).
  final Map<Type, List<EventHandler<dynamic>>> _handlers = {};
  final Map<String, int> _handledCounts = {};
  bool _running = false;
  bool _closed = false;
  bool _warned = false;
  // Generation guard: each consume loop captures the current generation and
  // exits as soon as a newer [start] bumped it. This keeps a single live
  // consume loop even when start() races stop()'s drain window (only the
  // current generation parks on the single idle slot, so nothing is orphaned).
  int _generation = 0;
  Completer<void>? _idle;
  Future<void> _loopDone = Future<void>.value();

  /// Events waiting to be consumed.
  int get queued => _queue.length;

  /// Delivered event counts, keyed by `'<KindEnum>.<kindName>'`.
  Map<String, int> get handledCounts => Map.unmodifiable(_handledCounts);

  /// Starts the consume loop. No-op if already running.
  ///
  /// If a previous [stop] is still draining, its (older-generation) consume
  /// loop exits immediately via the generation guard below, so only the
  /// newest loop ever parks on the idle slot or consumes the queue.
  Future<void> start() async {
    if (_running) return;
    _running = true;
    _closed = false;
    _loopDone = _consume(generation: ++_generation);
  }

  @override
  void dispatch(DispatcherEvent<dynamic> event) {
    if (_closed) return; // stopped: drop (YARN dispatcher is not restartable)
    _queue.add(event);
    if (_queue.length > _warnDepth) {
      if (!_warned) {
        _warned = true;
        final depth = _queue.length;
        _logger.w('$_tag queue depth $depth exceeds $_warnDepth');
        _onWarn?.call(depth);
      }
    } else {
      _warned = false;
    }
    _wake();
  }

  @override
  void registerFamily<K extends Enum>(Type kindType, EventHandler handler) {
    final family = _handlers.putIfAbsent(kindType, () => []);
    if (!family.contains(handler)) family.add(handler);
  }

  @override
  void unregister(EventHandler handler) {
    _handlers.removeWhere((_, family) {
      family.remove(handler);
      return family.isEmpty;
    });
  }

  /// Drains everything already queued, then closes the dispatcher.
  /// Events dispatched after [stop] begins are dropped.
  Future<void> stop() async {
    _running = false;
    _closed = true;
    _wake();
    await _loopDone;
  }

  void _wake() {
    final idle = _idle;
    _idle = null;
    idle?.complete();
  }

  Future<void> _consume({required int generation}) async {
    while (_running || _queue.isNotEmpty) {
      if (_queue.isEmpty) {
        // A newer start() replaced this loop: exit instead of parking (an
        // older-generation park would orphan the single idle slot).
        if (generation != _generation) return;
        final idle = Completer<void>();
        _idle = idle;
        await idle.future;
        continue;
      }
      _dispatchToListeners(_queue.removeFirst());
    }
  }

  void _dispatchToListeners(DispatcherEvent<dynamic> event) {
    final kindType = event.eventKind.runtimeType;
    final family = _handlers[kindType];
    if (family == null || family.isEmpty) {
      _logger.d('$_tag no handler for $kindType');
      return;
    }
    // Snapshot: a handler may register/unregister during delivery.
    for (final handler in List.of(family)) {
      try {
        handler.handle(event);
      } catch (error, stackTrace) {
        // Error isolation: log and continue with the next handler/event.
        // recordError: false — per-callback isolation must not surface global
        // error toasts / reports (precedent: TerminalObservationBus).
        _logger.e(
          '$_tag handler error for $kindType',
          error: error,
          stackTrace: stackTrace,
          recordError: false,
        );
      }
    }
    // Cast to Enum so the core EnumName extension applies (extension members
    // are not reachable through a dynamic receiver).
    final kindName = (event.eventKind as Enum).name;
    final key = '$kindType.$kindName';
    _handledCounts[key] = (_handledCounts[key] ?? 0) + 1;
  }
}
