import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/resource/resource_kind.dart';
import 'package:teampilot/services/resource/resource_materializer.dart';
import 'package:teampilot/services/storage/app_storage.dart';

import '../../support/post_frame_test_harness.dart';

void main() {
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  test('reconcile adds missing, removes stale, and is idempotent', () async {
    final fs = AppStorage.fs;
    final tmp = await fs.createTempDir(prefix: 'mat_test_');
    final srcA = fs.pathContext.join(tmp, 'srcA');
    final srcB = fs.pathContext.join(tmp, 'srcB');
    await fs.ensureDir(srcA);
    await fs.ensureDir(srcB);
    final kindDir = fs.pathContext.join(tmp, 'cfg', 'skills');

    final materializer = ResourceMaterializer(fs: fs);

    var result = await materializer.reconcile(
      kindDir: kindDir,
      desired: [ResourceRef(id: 'a', linkName: 'a', sourceDir: srcA)],
    );
    expect(result.errors, isEmpty);
    expect((await fs.listDir(kindDir)).map((e) => e.name), ['a']);

    await materializer.reconcile(
      kindDir: kindDir,
      desired: [ResourceRef(id: 'b', linkName: 'b', sourceDir: srcB)],
    );
    expect((await fs.listDir(kindDir)).map((e) => e.name), ['b']);

    final again = await materializer.reconcile(
      kindDir: kindDir,
      desired: [ResourceRef(id: 'b', linkName: 'b', sourceDir: srcB)],
    );
    expect(again.errors, isEmpty);
    expect((await fs.listDir(kindDir)).map((e) => e.name), ['b']);
  });

  test('reconcile records an error when source is missing', () async {
    final fs = AppStorage.fs;
    final tmp = await fs.createTempDir(prefix: 'mat_err_');
    final kindDir = fs.pathContext.join(tmp, 'skills');
    final result = await ResourceMaterializer(fs: fs).reconcile(
      kindDir: kindDir,
      desired: [
        ResourceRef(
          id: 'gone',
          linkName: 'gone',
          sourceDir: fs.pathContext.join(tmp, 'does-not-exist'),
        ),
      ],
    );
    expect(result.errors.single, contains('gone'));
  });
}
