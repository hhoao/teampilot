import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/services/file_tree/file_tree_visible_rows.dart';
import 'package:teampilot/services/file_tree_import/file_tree_drop_hit_test.dart';
import 'package:teampilot/services/io/filesystem.dart';
import 'package:teampilot/widgets/file_tree/file_tree_drop_region.dart';

FileTreeVisibleRow _row({
  required String path,
  required String name,
  required bool isDirectory,
  int depth = 0,
  bool isRoot = false,
  bool isEmptyPlaceholder = false,
}) {
  return FileTreeVisibleRow(
    path: path,
    entry: FsDirEntry(name: name, isDirectory: isDirectory),
    depth: depth,
    isRoot: isRoot,
    isEmptyPlaceholder: isEmptyPlaceholder,
  );
}

void main() {
  group('fileTreeCopyModifierPressed', () {
    test('macOS uses Option/Alt, not Control', () {
      expect(
        fileTreeCopyModifierPressed(
          platform: TargetPlatform.macOS,
          keys: {LogicalKeyboardKey.altLeft},
        ),
        isTrue,
      );
      expect(
        fileTreeCopyModifierPressed(
          platform: TargetPlatform.macOS,
          keys: {LogicalKeyboardKey.altRight},
        ),
        isTrue,
      );
      expect(
        fileTreeCopyModifierPressed(
          platform: TargetPlatform.macOS,
          keys: {LogicalKeyboardKey.controlLeft},
        ),
        isFalse,
      );
    });

    test('linux/windows uses Control, not Alt', () {
      expect(
        fileTreeCopyModifierPressed(
          platform: TargetPlatform.linux,
          keys: {LogicalKeyboardKey.controlLeft},
        ),
        isTrue,
      );
      expect(
        fileTreeCopyModifierPressed(
          platform: TargetPlatform.windows,
          keys: {LogicalKeyboardKey.controlRight},
        ),
        isTrue,
      );
      expect(
        fileTreeCopyModifierPressed(
          platform: TargetPlatform.linux,
          keys: {LogicalKeyboardKey.altLeft},
        ),
        isFalse,
      );
    });
  });

  group('resolveFileTreeDropAcceptAction', () {
    test('valid hit → ingest', () {
      expect(
        resolveFileTreeDropAcceptAction(
          const FileTreeDropHit(destDir: '/proj'),
        ),
        FileTreeDropAcceptAction.ingest,
      );
    });

    test('ontoSelf → rejectSelf (toast path)', () {
      expect(
        resolveFileTreeDropAcceptAction(
          const FileTreeDropHit(destDir: null, rejectedReason: 'ontoSelf'),
        ),
        FileTreeDropAcceptAction.rejectSelf,
      );
    });

    test('sameDir → ignore (silent no-op)', () {
      expect(
        resolveFileTreeDropAcceptAction(
          const FileTreeDropHit(destDir: null, rejectedReason: 'sameDir'),
        ),
        FileTreeDropAcceptAction.ignore,
      );
    });

    test('other invalid → ignore', () {
      expect(
        resolveFileTreeDropAcceptAction(const FileTreeDropHit(destDir: null)),
        FileTreeDropAcceptAction.ignore,
      );
    });
  });

  group('resolveOsHoverHighlight', () {
    test('row under pointer highlights that row', () {
      final highlight = resolveOsHoverHighlight(
        hit: const FileTreeDropHit(destDir: '/proj/src'),
        rowUnderPointer: '/proj/src',
      );
      expect(highlight.rowPath, '/proj/src');
      expect(highlight.panelHighlight, isFalse);
    });

    test('valid empty-area hit highlights dest + panel', () {
      final highlight = resolveOsHoverHighlight(
        hit: const FileTreeDropHit(destDir: '/proj'),
        rowUnderPointer: null,
      );
      expect(highlight.rowPath, '/proj');
      expect(highlight.panelHighlight, isTrue);
    });

    test('invalid hit clears highlight', () {
      final highlight = resolveOsHoverHighlight(
        hit: const FileTreeDropHit(destDir: null, rejectedReason: 'ontoSelf'),
        rowUnderPointer: '/proj/src',
      );
      expect(highlight.rowPath, isNull);
      expect(highlight.panelHighlight, isFalse);
    });
  });

  group('resolveFileTreePanelDropHit dest injection', () {
    final ctx = p.posix;

    test('folder row contentY maps to that folder as destDir', () {
      final rows = [
        _row(path: '/proj/src', name: 'src', isDirectory: true),
        _row(
          path: '/proj/src/a.txt',
          name: 'a.txt',
          isDirectory: false,
          depth: 1,
        ),
      ];

      final hit = resolveFileTreePanelDropHit(
        contentY: kFileTreeRowExtent * 0.5,
        visibleRows: rows,
        rootPaths: const ['/proj'],
        pathContextFor: (_) => ctx,
      );

      expect(hit.isValid, isTrue);
      expect(hit.destDir, '/proj/src');
    });

    test('file row contentY maps to parent destDir', () {
      final rows = [
        _row(path: '/proj/src', name: 'src', isDirectory: true),
        _row(
          path: '/proj/src/a.txt',
          name: 'a.txt',
          isDirectory: false,
          depth: 1,
        ),
      ];

      final hit = resolveFileTreePanelDropHit(
        contentY: kFileTreeRowExtent * 1.5,
        visibleRows: rows,
        rootPaths: const ['/proj'],
        pathContextFor: (_) => ctx,
      );

      expect(hit.isValid, isTrue);
      expect(hit.destDir, '/proj/src');
    });

    test('below last row uses nearest multi-root band', () {
      final rows = [
        _row(path: '/a', name: 'a', isDirectory: true, isRoot: true),
        _row(path: '/a/x.txt', name: 'x.txt', isDirectory: false, depth: 1),
        _row(path: '/b', name: 'b', isDirectory: true, isRoot: true),
        _row(path: '/b/y.txt', name: 'y.txt', isDirectory: false, depth: 1),
      ];

      final hit = resolveFileTreePanelDropHit(
        contentY: kFileTreeRowExtent * 5,
        visibleRows: rows,
        rootPaths: const ['/a', '/b'],
        pathContextFor: (_) => ctx,
      );

      expect(hit.isValid, isTrue);
      expect(hit.destDir, '/b');
    });

    test('empty visible rows falls back to single root', () {
      final hit = resolveFileTreePanelDropHit(
        contentY: 12,
        visibleRows: const [],
        rootPaths: const ['/proj'],
        pathContextFor: (_) => ctx,
      );

      expect(hit.isValid, isTrue);
      expect(hit.destDir, '/proj');
    });

    test('below last row single-root resolves to that root', () {
      final rows = [
        _row(path: '/proj/src', name: 'src', isDirectory: true),
      ];

      final hit = resolveFileTreePanelDropHit(
        contentY: kFileTreeRowExtent * 3,
        visibleRows: rows,
        rootPaths: const ['/proj'],
        pathContextFor: (_) => ctx,
      );

      expect(hit.isValid, isTrue);
      expect(hit.destDir, '/proj');
    });

    test('empty placeholder row resolves to parent dir', () {
      final rows = [
        _row(
          path: '/proj/emptyDir',
          name: '(empty)',
          isDirectory: false,
          depth: 1,
          isEmptyPlaceholder: true,
        ),
      ];

      final hit = resolveFileTreePanelDropHit(
        contentY: kFileTreeRowExtent * 0.4,
        visibleRows: rows,
        rootPaths: const ['/proj'],
        pathContextFor: (_) => ctx,
      );

      expect(hit.isValid, isTrue);
      expect(hit.destDir, '/proj/emptyDir');
    });

    test('in-tree onto self rejects', () {
      final rows = [
        _row(path: '/proj/src', name: 'src', isDirectory: true),
      ];

      final hit = resolveFileTreePanelDropHit(
        contentY: kFileTreeRowExtent * 0.2,
        visibleRows: rows,
        rootPaths: const ['/proj'],
        pathContextFor: (_) => ctx,
        sourcePaths: const ['/proj/src'],
      );

      expect(hit.isValid, isFalse);
      expect(hit.rejectedReason, 'ontoSelf');
      expect(
        resolveFileTreeDropAcceptAction(hit),
        FileTreeDropAcceptAction.rejectSelf,
      );
    });

    test('in-tree empty-area drop into own root folder is ignored', () {
      final rows = [
        _row(path: '/proj/src', name: 'src', isDirectory: true),
        _row(
          path: '/proj/src/a.txt',
          name: 'a.txt',
          isDirectory: false,
          depth: 1,
        ),
      ];

      final hit = resolveFileTreePanelDropHit(
        contentY: kFileTreeRowExtent * 3,
        visibleRows: rows,
        rootPaths: const ['/proj'],
        pathContextFor: (_) => ctx,
        sourcePaths: const ['/proj/root.txt'],
      );

      expect(hit.isValid, isFalse);
      expect(hit.rejectedReason, 'sameDir');
      expect(
        resolveFileTreeDropAcceptAction(hit),
        FileTreeDropAcceptAction.ignore,
      );
    });

    test('scroll offset is applied via contentY helper', () {
      expect(fileTreeDropContentY(listLocalY: 10, scrollOffset: 72), 82);
    });
  });
}
