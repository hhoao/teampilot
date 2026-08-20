import 'dart:async';

import 'catalog_kind.dart';

class CatalogMutationEvent {
  const CatalogMutationEvent({
    required this.kind,
    required this.op,
    required this.ids,
    required this.workspaceId,
  });

  final String kind;
  final CatalogOp op;
  final List<String> ids;
  final String workspaceId;
}

class CatalogMutationBus {
  CatalogMutationBus()
    : _controller = StreamController<CatalogMutationEvent>.broadcast();

  final StreamController<CatalogMutationEvent> _controller;

  Stream<CatalogMutationEvent> listen() => _controller.stream;

  void emit(CatalogMutationEvent event) {
    _controller.add(event);
  }
}
