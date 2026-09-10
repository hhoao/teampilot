import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/catalog/catalog_kind.dart';
import 'package:teampilot/services/catalog/catalog_mutation_bus.dart';
import 'package:teampilot/services/event/async_dispatcher.dart';
import 'package:teampilot/services/event/dispatcher.dart';

void main() {
  test('emit reaches both legacy listen() and dispatcher handlers', () async {
    final d = AsyncDispatcher()..start();
    final bus = CatalogMutationBus(dispatcher: d);

    final legacy = <CatalogMutationEvent>[];
    bus.listen().listen(legacy.add);
    final viaDispatcher = <CatalogMutationEvent>[];
    d.registerFamily<CatalogMutationKind>(
      CatalogMutationKind.mutated.runtimeType,
      _Handler(viaDispatcher),
    );

    const e = CatalogMutationEvent(
      kind: 'skill',
      op: CatalogOp.create,
      ids: ['local:x'],
      workspaceId: 'w-1',
    );
    bus.emit(e);
    await d.stop();
    // Broadcast-controller delivery lands one event-loop hop after the
    // relay handler ran; wait widened, assertions untouched.
    await Future<void>.delayed(Duration.zero);

    expect(legacy.single, same(e));
    expect(viaDispatcher.single, same(e));
  });
}

class _Handler implements EventHandler<CatalogMutationEvent> {
  _Handler(this.events);

  final List<CatalogMutationEvent> events;

  @override
  void handle(CatalogMutationEvent event) => events.add(event);
}
