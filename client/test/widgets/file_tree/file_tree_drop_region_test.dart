import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/services/file_tree/file_tree_visible_rows.dart';
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

  group('resolveFileTreePanelDropHit dest injection', () {
    final ctx = p.posix;

    test('folder row contentY maps to that folder as destDir', () {
      final rows = [
        _row(path: '/proj/src', name: 'src', isDirectory: true),
        _row(path: '/proj/src/a.txt', name: 'a.txt', isDirectory: false, depth: 1),
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
        _row(path: '/proj/src/a.txt', name: 'a.txt', isDirectory: false, depth: 1),
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
    });

    test('scroll offset is applied via contentY helper', () {
      expect(
        fileTreeDropContentY(listLocalY: 10, scrollOffset: 72),
        82,
      );
    });
  });
}
