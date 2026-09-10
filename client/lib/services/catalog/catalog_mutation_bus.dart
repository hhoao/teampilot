import 'dart:async';

import '../event/dispatcher.dart';
import 'catalog_kind.dart';

/// Family kind for the central dispatcher. Single-member: the rich payload
/// (kind/op/ids) stays on the event itself — the dispatcher only routes.
enum CatalogMutationKind { mutated }

class CatalogMutationEvent implements DispatcherEvent<CatalogMutationKind> {
  const CatalogMutationEvent({
    required this.kind,
    required this.op,
    required this.ids,
    required this.workspaceId,
    DateTime? timestamp,
  }) : _explicitTimestamp = timestamp;

  /// Catalog domain kind ('skill' / 'plugin' / ...). Unrelated to
  /// [eventKind], the dispatcher family kind.
  final String kind;
  final CatalogOp op;
  final List<String> ids;
  final String workspaceId;

  final DateTime? _explicitTimestamp;

  /// When the mutation occurred; falls back to read time when the emitter
  /// did not stamp one (legacy call sites predate the timestamp contract).
  @override
  DateTime get timestamp => _explicitTimestamp ?? DateTime.now();

  @override
  CatalogMutationKind get eventKind => CatalogMutationKind.mutated;
}

class CatalogMutationBus {
  CatalogMutationBus({Dispatcher? dispatcher})
    : _dispatcher = dispatcher,
      _controller = StreamController<CatalogMutationEvent>.broadcast() {
    // Single source of truth: when a dispatcher is wired, its handler loop
    // copies every dispatched event back into the local controller, so
    // listen() subscribers see identical events with identical timing
    // guarantees (broadcast, same instances). Without a dispatcher (tests
    // constructing the bus bare), emit() feeds the controller directly.
    final d = dispatcher;
    if (d != null) {
      _relay = _RelayHandler(_controller);
      d.registerFamily<CatalogMutationKind>(
        CatalogMutationKind.mutated.runtimeType,
        _relay!,
      );
    }
  }

  final Dispatcher? _dispatcher;
  final StreamController<CatalogMutationEvent> _controller;
  _RelayHandler? _relay;
  bool _closed = false;

  Stream<CatalogMutationEvent> listen() => _controller.stream;

  void emit(CatalogMutationEvent event) {
    if (_closed) return;
    final d = _dispatcher;
    if (d != null) {
      d.dispatch(event);
    } else {
      _controller.add(event);
    }
  }

  /// Unregisters this bus's relay handler from the dispatcher (if wired) and
  /// closes the local controller.
  ///
  /// The app-lifetime central dispatcher outlives shells: a retried bootstrap
  /// builds a new bus while the failed shell's relay handler would otherwise
  /// stay registered forever, fanning mutations into the dead shell's
  /// listeners (legacy bare buses never received events after their emitters
  /// died). Idempotent.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    final relay = _relay;
    if (relay != null) {
      // Detach first so a handler snapshot taken mid-delivery by the
      // dispatcher's consume loop no-ops even after unregister raced it.
      relay.detach();
      _dispatcher?.unregister(relay);
    }
    await _controller.close();
  }
}

/// Copies dispatcher-delivered events back into the bus's local controller.
class _RelayHandler implements EventHandler<CatalogMutationEvent> {
  _RelayHandler(this._controller);

  final StreamController<CatalogMutationEvent> _controller;
  bool _detached = false;

  /// Stops relaying; used by [CatalogMutationBus.close] so in-flight
  /// dispatcher deliveries cannot reach a disposed bus's listeners.
  void detach() => _detached = true;

  @override
  void handle(CatalogMutationEvent event) {
    if (_detached) return;
    _controller.add(event);
  }
}
