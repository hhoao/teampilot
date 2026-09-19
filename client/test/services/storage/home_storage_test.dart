import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/services/storage/app_paths.dart';
import 'package:teampilot/services/storage/home_storage.dart';
import 'package:teampilot/services/storage/runtime_context.dart';

import '../../support/in_memory_filesystem.dart';

RuntimeContext _context({
  required InMemoryFilesystem filesystem,
  String home = '/home/test',
  String appDataRoot = '/tp',
}) {
  return RuntimeContext(
    target: RuntimeTarget.local(),
    filesystem: filesystem,
    home: home,
    cwd: home,
    appDataRoot: appDataRoot,
    paths: AppPaths(appDataRoot),
  );
}

void main() {
  group('HomeStorage', () {
    test('getters forward to the current context', () {
      final fs = InMemoryFilesystem();
      final ctx = _context(
        filesystem: fs,
        home: '/home/a',
        appDataRoot: '/tp/a',
      );
      final storage = HomeStorage(ctx);

      expect(storage.context, same(ctx));
      expect(storage.fs, same(fs));
      expect(storage.paths, same(ctx.paths));
      expect(storage.home, '/home/a');
      expect(storage.cwd, '/home/a');
      expect(storage.appDataRoot, '/tp/a');
      expect(storage.usesPosixPaths, ctx.usesPosixPaths);
      expect(storage.generation, 0);
    });

    test(
      'swap publishes the new context before the retire drain completes',
      () async {
        final oldCtx = _context(
          filesystem: InMemoryFilesystem(),
          home: '/home/old',
        );
        final newFs = InMemoryFilesystem();
        final newCtx = _context(filesystem: newFs, home: '/home/new');
        final retireGate = Completer<void>();
        var retireCalls = 0;
        final storage = HomeStorage(
          oldCtx,
          retire: (old) async {
            retireCalls++;
            await retireGate.future;
          },
        );

        final swapDone = storage.swap(newCtx);

        // Synchronous publish: new operations must see the new plane before the
        // old transport's drain finishes.
        expect(storage.context, same(newCtx));
        expect(storage.fs, same(newFs));
        expect(storage.home, '/home/new');
        expect(
          retireCalls,
          1,
          reason: 'retire must have started (awaiting drain)',
        );

        retireGate.complete();
        await swapDone;
        expect(retireCalls, 1);
      },
    );

    test('swap increments generation and emits changes exactly once', () async {
      final oldCtx = _context(filesystem: InMemoryFilesystem());
      final newCtx = _context(
        filesystem: InMemoryFilesystem(),
        home: '/home/new',
      );
      final storage = HomeStorage(oldCtx);
      final changes = <StoragePlaneChange>[];
      final sub = storage.changes.listen(changes.add);

      await storage.swap(newCtx);

      expect(storage.generation, 1);
      expect(changes, hasLength(1));
      expect(changes.single.oldContext, same(oldCtx));
      expect(changes.single.newContext, same(newCtx));
      expect(changes.single.generation, 1);
      await sub.cancel();
    });

    test('swapping to the identical context is a full no-op', () async {
      final ctx = _context(filesystem: InMemoryFilesystem());
      var retireCalls = 0;
      final storage = HomeStorage(
        ctx,
        retire: (old) async {
          retireCalls++;
        },
      );
      final changes = <StoragePlaneChange>[];
      final sub = storage.changes.listen(changes.add);

      await storage.swap(ctx);

      expect(storage.context, same(ctx));
      expect(storage.generation, 0);
      expect(changes, isEmpty);
      expect(retireCalls, 0, reason: 'identical swap must not retire');
      await sub.cancel();
    });

    test(
      'forTesting builds a native context bound to the given filesystem',
      () {
        final fs = InMemoryFilesystem();
        final storage = HomeStorage.forTesting(
          filesystem: fs,
          paths: AppPaths('/tp-test'),
          home: '/home/tester',
          cwd: '/home/tester/work',
        );

        expect(storage.context.target.id, RuntimeTarget.localId);
        expect(storage.fs, same(fs));
        expect(storage.home, '/home/tester');
        expect(storage.cwd, '/home/tester/work');
        expect(storage.appDataRoot, '/tp-test');
        expect(storage.context.pathsFromCache, isFalse);
      },
    );
  });
}
