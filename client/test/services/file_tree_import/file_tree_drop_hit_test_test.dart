import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/services/file_tree_import/file_tree_drop_hit_test.dart';

void main() {
  group('resolveFileTreeDropDest', () {
    final ctx = p.Context(style: p.Style.posix);
    const root = '/workspace';
    const folder = '/workspace/lib';
    const file = '/workspace/lib/main.dart';

    test('folder row resolves to that folder path', () {
      final hit = resolveFileTreeDropDest(
        kind: FileTreeDropRowKind.folder,
        rowPath: folder,
        pathContext: ctx,
      );

      expect(hit.isValid, isTrue);
      expect(hit.destDir, folder);
      expect(hit.rejectedReason, isNull);
    });

    test('file row resolves to parent directory', () {
      final hit = resolveFileTreeDropDest(
        kind: FileTreeDropRowKind.file,
        rowPath: file,
        pathContext: ctx,
      );

      expect(hit.isValid, isTrue);
      expect(hit.destDir, folder);
      expect(hit.rejectedReason, isNull);
    });

    test('rootChrome row resolves to the root path', () {
      final hit = resolveFileTreeDropDest(
        kind: FileTreeDropRowKind.rootChrome,
        rowPath: root,
        pathContext: ctx,
      );

      expect(hit.isValid, isTrue);
      expect(hit.destDir, root);
      expect(hit.rejectedReason, isNull);
    });

    test('empty row with candidate root uses that path', () {
      final hit = resolveFileTreeDropDest(
        kind: FileTreeDropRowKind.empty,
        rowPath: root,
        pathContext: ctx,
      );

      expect(hit.isValid, isTrue);
      expect(hit.destDir, root);
      expect(hit.rejectedReason, isNull);
    });

    test('rejects in-tree drop onto self', () {
      final hit = resolveFileTreeDropDest(
        kind: FileTreeDropRowKind.folder,
        rowPath: folder,
        pathContext: ctx,
        sourcePaths: [folder],
      );

      expect(hit.isValid, isFalse);
      expect(hit.destDir, isNull);
      expect(hit.rejectedReason, 'ontoSelf');
    });

    test('rejects in-tree drop onto descendant folder', () {
      const child = '/workspace/lib/widgets';
      final hit = resolveFileTreeDropDest(
        kind: FileTreeDropRowKind.folder,
        rowPath: child,
        pathContext: ctx,
        sourcePaths: [folder],
      );

      expect(hit.isValid, isFalse);
      expect(hit.destDir, isNull);
      expect(hit.rejectedReason, 'ontoSelf');
    });

    test('rejects in-tree file row when parent equals source', () {
      final hit = resolveFileTreeDropDest(
        kind: FileTreeDropRowKind.file,
        rowPath: file,
        pathContext: ctx,
        sourcePaths: [folder],
      );

      expect(hit.isValid, isFalse);
      expect(hit.destDir, isNull);
      expect(hit.rejectedReason, 'ontoSelf');
    });

    test('ignores in-tree drop onto the source own folder', () {
      final hit = resolveFileTreeDropDest(
        kind: FileTreeDropRowKind.folder,
        rowPath: folder,
        pathContext: ctx,
        sourcePaths: [file],
      );

      expect(hit.isValid, isFalse);
      expect(hit.destDir, isNull);
      expect(hit.rejectedReason, 'sameDir');
    });

    test('ignores in-tree drop onto a sibling file row in the same folder',
        () {
      const sibling = '/workspace/lib/other.dart';
      final hit = resolveFileTreeDropDest(
        kind: FileTreeDropRowKind.file,
        rowPath: sibling,
        pathContext: ctx,
        sourcePaths: [file],
      );

      expect(hit.isValid, isFalse);
      expect(hit.destDir, isNull);
      expect(hit.rejectedReason, 'sameDir');
    });

    test('ignores drop onto root when all sources sit at the root level', () {
      const rootFile = '/workspace/pubspec.yaml';
      final hit = resolveFileTreeDropDest(
        kind: FileTreeDropRowKind.rootChrome,
        rowPath: root,
        pathContext: ctx,
        sourcePaths: [rootFile],
      );

      expect(hit.isValid, isFalse);
      expect(hit.rejectedReason, 'sameDir');
    });

    test('still allows drop when only some sources are already in dest dir',
        () {
      final hit = resolveFileTreeDropDest(
        kind: FileTreeDropRowKind.folder,
        rowPath: folder,
        pathContext: ctx,
        sourcePaths: [file, '/workspace/other.dart'],
      );

      expect(hit.isValid, isTrue);
      expect(hit.destDir, folder);
    });

    test('allows external drop without source paths', () {
      final hit = resolveFileTreeDropDest(
        kind: FileTreeDropRowKind.folder,
        rowPath: folder,
        pathContext: ctx,
      );

      expect(hit.isValid, isTrue);
      expect(hit.destDir, folder);
    });

    test('normalizes destination paths', () {
      final hit = resolveFileTreeDropDest(
        kind: FileTreeDropRowKind.file,
        rowPath: '/workspace/lib/../lib/main.dart',
        pathContext: ctx,
      );

      expect(hit.isValid, isTrue);
      expect(hit.destDir, '/workspace/lib');
    });
  });

  group('resolveNearestRootDest', () {
    const bands = [
      (rootPath: '/repo-a', top: 0.0, bottom: 100.0),
      (rootPath: '/repo-b', top: 120.0, bottom: 220.0),
    ];

    test('returns root whose band contains localY', () {
      expect(
        resolveNearestRootDest(localY: 50, rootBands: bands),
        '/repo-a',
      );
      expect(
        resolveNearestRootDest(localY: 150, rootBands: bands),
        '/repo-b',
      );
    });

    test('returns nearest root centerY when localY is in a gap', () {
      expect(
        resolveNearestRootDest(localY: 110, rootBands: bands),
        '/repo-a',
      );
      expect(
        resolveNearestRootDest(localY: 111, rootBands: bands),
        '/repo-b',
      );
    });

    test('returns nearest root when localY is outside all bands', () {
      expect(
        resolveNearestRootDest(localY: -20, rootBands: bands),
        '/repo-a',
      );
      expect(
        resolveNearestRootDest(localY: 300, rootBands: bands),
        '/repo-b',
      );
    });
  });
}
