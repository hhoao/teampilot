import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/catalog/catalog_kind.dart';
import 'package:teampilot/services/catalog/catalog_mutation_bus.dart';
import 'package:teampilot/services/event/async_dispatcher.dart';

void main() {
  group('bootstrap-failure catalog bus teardown', () {
    // Behavioral model of the retried bootstrap: the app-lifetime dispatcher
    // outlives shells, and each CatalogRuntime.assemble registers a new relay
    // on it. When the failed shell's bus is closed before the retry, events
    // emitted by the new shell's bus must not reach the dead shell.
    test(
      'new bus mutations do not reach a closed old bus on one dispatcher',
      () async {
        final d = AsyncDispatcher()..start();
        final oldBus = CatalogMutationBus(dispatcher: d);
        final newBus = CatalogMutationBus(dispatcher: d);

        final stale = <CatalogMutationEvent>[];
        final fresh = <CatalogMutationEvent>[];
        oldBus.listen().listen(stale.add);
        newBus.listen().listen(fresh.add);
        await oldBus.close();

        const e = CatalogMutationEvent(
          kind: 'skill',
          op: CatalogOp.create,
          ids: ['local:x'],
          workspaceId: 'w-1',
        );
        newBus.emit(e);
        await d.stop();
        await Future<void>.delayed(Duration.zero);

        expect(stale, isEmpty);
        expect(fresh.single, same(e));
      },
    );

    // The full TeamPilotBootstrap retry path (buildAppShell succeeds, then
    // bootstrapAppData throws, then the user retries) is not widget-testable:
    // buildAppShell wires the entire production app (storage, SSH, cubits)
    // behind ~90 required AppShell dependencies. So the _start failure-path
    // wiring is pinned at the source level instead, following the precedent
    // of clean_end_state_test.dart reading lib/app/app_shell.dart.
    test(
      'app_shell failure path closes the discarded shell catalog bus',
      () async {
        final src = File('lib/app/app_shell.dart').readAsStringSync();

        // The seam exists: AppShell exposes its assembled catalog runtime.
        expect(
          src.contains('final CatalogRuntime? catalogRuntime;'),
          isTrue,
          reason: 'AppShell must expose catalogRuntime for teardown on failure',
        );
        // The seam is wired: buildAppShell passes the assembled runtime through.
        expect(
          src.contains('catalogRuntime: catalogRuntime,'),
          isTrue,
          reason:
              'AppShell construction must pass the assembled catalogRuntime',
        );
        // The seam is used: the bootstrap-failure catch (which covers
        // bootstrapAppData throwing after the shell was built) closes the bus.
        expect(
          src.contains('builtShell?.catalogRuntime?.bus.close();'),
          isTrue,
          reason:
              'the _start failure catch must close the discarded shell bus '
              'before a retry constructs a new one',
        );
      },
    );
  });
}
