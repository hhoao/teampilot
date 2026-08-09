import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/git_status.dart';
import 'package:teampilot/services/git/git_changes_visible_rows.dart';

GitFileChange change(String path, {bool staged = false, GitChangeKind kind = GitChangeKind.modified}) =>
    GitFileChange(path: path, kind: kind, staged: staged);

void main() {
  test('mergeGitChangesByPath dedups partial-staged paths, staged side wins', () {
    final merged = mergeGitChangesByPath(
      staged: [
        change('a/b.txt', staged: true, kind: GitChangeKind.added),
        change('c.txt', staged: true),
      ],
      unstaged: [change('a/b.txt'), change('d.txt')],
    );
    final paths = merged.map((c) => c.path).toSet();
    expect(paths, {'a/b.txt', 'c.txt', 'd.txt'});
    final ab = merged.firstWhere((c) => c.path == 'a/b.txt');
    expect(ab.staged, isTrue);
    expect(ab.kind, GitChangeKind.added); // staged side kind wins
  });

  test('unified tree gives folder tri-state subtree counts', () {
    final view = visibleUnifiedGitChangesTreeView(
      staged: [
        change('domain/Foo.java', staged: true),
        change('domain/core/Bar.java', staged: true),
      ],
      unstaged: [change('domain/Baz.java'), change('domain/core/Qux.java')],
      expandedFolderPaths: const {'domain'},
    );
    final folderRows = view.rows.where((r) => r.isFolder).toList();
    // root-level folder 'domain': 2 staged of 4 total
    final domain = folderRows.firstWhere((r) => r.folderPath == 'domain');
    expect(domain.subtreeTotalCount, 4);
    expect(domain.subtreeStagedCount, 2);
    // nested folder 'domain/core': 1 staged of 2 total
    final core = folderRows.firstWhere((r) => r.folderPath == 'domain/core');
    expect(core.subtreeTotalCount, 2);
    expect(core.subtreeStagedCount, 1);
    expect(view.stagedCount, 2);
    expect(view.totalCount, 4);
  });

  test('collapsed folders still report subtree counts', () {
    final view = visibleUnifiedGitChangesTreeView(
      staged: [change('a/x.java', staged: true)],
      unstaged: [change('a/y.java')],
      expandedFolderPaths: const <String>{},
    );
    final folder = view.rows.singleWhere((r) => r.isFolder);
    expect(folder.subtreeTotalCount, 2);
    expect(folder.subtreeStagedCount, 1);
    expect(view.rows.where((r) => !r.isFolder), isEmpty); // children not emitted
  });

  test('min content width accounts for checkbox + badge per row type', () {
    const style = TextStyle(fontSize: 12);
    // Equal-width labels (Ahem font: every glyph is fontSize wide).
    final file = GitChangesVisibleRow.file(
      change: change('aaaaa'),
      depth: 0,
    );
    final folder = GitChangesVisibleRow.folder(
      folderPath: 'aaaaa',
      name: 'aaaaa',
      depth: 0,
      subtreeStagedCount: 0,
      subtreeTotalCount: 1,
    );
    final wFile = gitChangesMinContentWidth(
      rows: [file],
      fileLabelStyle: style,
      folderLabelStyle: style,
    );
    final wFolder = gitChangesMinContentWidth(
      rows: [folder],
      fileLabelStyle: style,
      folderLabelStyle: style,
    );
    // Equal labels → the difference is (file leading + badge) − (folder
    // leading), i.e. (checkbox+icon+gap + 22) − (chevron+checkbox+icon+gap).
    expect(
      wFile - wFolder,
      closeTo(kGitChangesTrailingBadgeWidth - 16, 1), // 22 − chevron slot
    );
    expect(wFile, greaterThan(100));
  });
}
