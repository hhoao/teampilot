import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/catalog/catalog_kind.dart';
import 'package:teampilot/services/catalog/catalog_mutation_bus.dart';

void main() {
  test('listen is invoked with the same ids as the emitted event', () async {
    final bus = CatalogMutationBus();
    CatalogMutationEvent? received;
    final sub = bus.listen().listen((event) => received = event);

    const event = CatalogMutationEvent(
      kind: 'skill',
      op: CatalogOp.create,
      ids: ['local:hello-skill'],
      workspaceId: 'ws-1',
    );
    bus.emit(event);
    await Future<void>.delayed(Duration.zero);

    expect(received, isNotNull);
    expect(received!.kind, 'skill');
    expect(received!.op, CatalogOp.create);
    expect(received!.ids, ['local:hello-skill']);
    expect(received!.workspaceId, 'ws-1');
    await sub.cancel();
  });
}
