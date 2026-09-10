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
      d.registerFamily<CatalogMutationKind>(
        CatalogMutationKind.mutated.runtimeType,
        _RelayHandler(_controller),
      );
    }
  }

  final Dispatcher? _dispatcher;
  final StreamController<CatalogMutationEvent> _controller;

  Stream<CatalogMutationEvent> listen() => _controller.stream;

  void emit(CatalogMutationEvent event) {
    final d = _dispatcher;
    if (d != null) {
      d.dispatch(event);
    } else {
      _controller.add(event);
    }
  }
}

/// Copies dispatcher-delivered events back into the bus's local controller.
class _RelayHandler implements EventHandler<CatalogMutationEvent> {
  const _RelayHandler(this._controller);

  final StreamController<CatalogMutationEvent> _controller;

  @override
  void handle(CatalogMutationEvent event) => _controller.add(event);
}
