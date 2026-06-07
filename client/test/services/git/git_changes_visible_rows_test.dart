import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/git_status.dart';
import 'package:teampilot/services/git/git_changes_visible_rows.dart';

void main() {
  test('visibleGitChangesRows nests files under expanded folders', () {
    const changes = [
      GitFileChange(
        path: 'src/utils/foo.dart',
        kind: GitChangeKind.modified,
        staged: false,
      ),
      GitFileChange(
        path: 'readme.md',
        kind: GitChangeKind.modified,
        staged: false,
      ),
    ];

    final rows = visibleGitChangesRows(
      changes: changes,
      expandedFolderPaths: {'src', 'src/utils'},
    );

    expect(rows.map((r) => r.isFolder ? 'D:${r.name}' : 'F:${r.change!.path}'), [
      'D:src',
      'D:utils',
      'F:src/utils/foo.dart',
      'F:readme.md',
    ]);
  });

  test('visibleGitChangesRows hides nested files when folder collapsed', () {
    const changes = [
      GitFileChange(
        path: 'src/main.dart',
        kind: GitChangeKind.modified,
        staged: false,
      ),
    ];

    final rows = visibleGitChangesRows(
      changes: changes,
      expandedFolderPaths: {},
    );

    expect(rows, [
      isA<GitChangesVisibleRow>().having((r) => r.isFolder, 'folder', isTrue),
    ]);
  });

  test('gitChangesMinContentWidth accounts for depth and trailing actions', () {
    const fileStyle = TextStyle(fontSize: 12);
    const folderStyle = TextStyle(fontSize: 12, fontWeight: FontWeight.w500);
    final rows = [
      const GitChangesVisibleRow.folder(
        folderPath: 'src',
        name: 'src',
        depth: 0,
      ),
      GitChangesVisibleRow.file(
        change: const GitFileChange(
          path: 'src/very-long-filename.dart',
          kind: GitChangeKind.modified,
          staged: false,
        ),
        depth: 1,
      ),
    ];

    final width = gitChangesMinContentWidth(
      rows: rows,
      fileLabelStyle: fileStyle,
      folderLabelStyle: folderStyle,
    );
    expect(width, greaterThan(200));
  });

  test('gitChangesDefaultExpandedFolders includes all directory prefixes', () {
    const changes = [
      GitFileChange(
        path: 'src/utils/foo.dart',
        kind: GitChangeKind.modified,
        staged: false,
      ),
    ];

    expect(
      gitChangesDefaultExpandedFolders(changes),
      {'src', 'src/utils'},
    );
  });
}
