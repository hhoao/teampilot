import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/launch/apply_plan.dart';
import 'package:teampilot/services/launch/work_path_projector.dart';

import '../../support/in_memory_filesystem.dart';

void main() {
  test('copyTree of provided install dir becomes symlink', () async {
    final sourceFs = InMemoryFilesystem();
    final workFs = InMemoryFilesystem();
    await sourceFs.writeString('/h/plugins/installed/foo/a.txt', 'A');
    await workFs.ensureDir('/w/plugins/installed/foo');
    final manifest = LaunchManifest()
      ..copyTree(
        source: '/h/plugins/installed/foo',
        destination: '/w/sessions/pool/foo',
      );
    final built = await buildApplyPlan(
      manifest: manifest,
      sourceFs: sourceFs,
      workFs: workFs,
      homeRoot: '/h',
      workRoot: '/w',
    );
    expect(built.providedLinks, 1);
    expect(built.plan.ops, hasLength(1));
    final op = built.plan.ops.single as ApplySymlink;
    expect(op.linkPath, '/w/sessions/pool/foo');
    expect(op.target, '/w/plugins/installed/foo');
  });

  test('copyTree when work dir missing becomes hashed tree', () async {
    final sourceFs = InMemoryFilesystem();
    final workFs = InMemoryFilesystem();
    await sourceFs.writeBytes('/h/plugins/installed/foo/bin.dat', [0, 1, 255]);
    final manifest = LaunchManifest()
      ..copyTree(
        source: '/h/plugins/installed/foo',
        destination: '/w/sessions/pool/foo',
      );
    final built = await buildApplyPlan(
      manifest: manifest,
      sourceFs: sourceFs,
      workFs: workFs,
      homeRoot: '/h',
      workRoot: '/w',
    );
    expect(built.providedLinks, 0);
    final tree = built.plan.ops.whereType<ApplyTree>().single;
    expect(tree.dest, '/w/sessions/pool/foo');
    expect(tree.entries.single.rel, 'bin.dat');
    final bytes = await built.blobs.open(tree.entries.single.sha256);
    expect(bytes, [0, 1, 255]);
  });

  test('provided copyTree is materialized when later op mutates it', () async {
    final sourceFs = InMemoryFilesystem();
    final workFs = InMemoryFilesystem();
    await sourceFs.writeString('/h/plugins/installed/foo/a.txt', 'A');
    await workFs.ensureDir('/w/plugins/installed/foo');
    final manifest = LaunchManifest()
      ..copyTree(source: '/h/plugins/installed/foo', destination: '/w/sess/foo')
      ..writeFile('/w/sess/foo/stamp.json', '{}');

    final built = await buildApplyPlan(
      manifest: manifest,
      sourceFs: sourceFs,
      workFs: workFs,
      homeRoot: '/h',
      workRoot: '/w',
    );

    expect(built.providedLinks, 0);
    expect(built.plan.ops.whereType<ApplySymlink>(), isEmpty);
    expect(built.plan.ops.whereType<ApplyTree>(), hasLength(1));
    expect(built.plan.ops.whereType<ApplyWriteInline>(), hasLength(1));
  });

  test('same path string different file bytes is not provided', () async {
    final sourceFs = InMemoryFilesystem();
    final workFs = InMemoryFilesystem();
    await sourceFs.writeString('/tp/a.txt', 'local');
    await workFs.writeString('/tp/a.txt', 'remote');
    final manifest = LaunchManifest()
      ..copyFile(source: '/tp/a.txt', destination: '/tp/sess/a.txt');
    final built = await buildApplyPlan(
      manifest: manifest,
      sourceFs: sourceFs,
      workFs: workFs,
      homeRoot: '/tp',
      workRoot: '/tp',
    );
    expect(built.providedLinks, 0);
    expect(built.plan.ops.single, isA<ApplyWriteBlob>());
  });

  test('writeFile at 4096 stays inline; 4097 is blob', () async {
    final fs = InMemoryFilesystem();
    final manifest = LaunchManifest()
      ..writeFile('/w/small.txt', 'a' * 4096)
      ..writeFile('/w/big.txt', 'a' * 4097);
    final built = await buildApplyPlan(
      manifest: manifest,
      sourceFs: fs,
      workFs: fs,
      homeRoot: '/w',
      workRoot: '/w',
    );
    expect(built.plan.ops[0], isA<ApplyWriteInline>());
    expect(built.plan.ops[1], isA<ApplyWriteBlob>());
  });

  test('unprojectable symlink target fails staging', () async {
    final fs = InMemoryFilesystem();
    final manifest = LaunchManifest()
      ..symlink(linkPath: '/w/l', target: '/not/in/roots');
    expect(
      () => buildApplyPlan(
        manifest: manifest,
        sourceFs: fs,
        workFs: fs,
        homeRoot: '/h',
        workRoot: '/w',
      ),
      throwsStateError,
    );
  });
}
