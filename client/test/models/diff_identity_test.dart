import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/workbench/workbench_tab.dart';
import 'package:teampilot/models/diff_identity.dart';
import 'package:teampilot/models/git_compare.dart';

void main() {
  group('ScmDiffIdentity', () {
    test('storage key encodes mode', () {
      expect(
        const ScmDiffIdentity('/r/a.dart', ScmDiffMode.staged).storageKey,
        '/r/a.dart::scm.staged',
      );
      expect(
        const ScmDiffIdentity('/r/a.dart', ScmDiffMode.changes).storageKey,
        '/r/a.dart::scm.changes',
      );
    });

    test('only unstaged is a writable working tree', () {
      expect(
        const ScmDiffIdentity('/r/a.dart', ScmDiffMode.unstaged)
            .isWritableWorkingTree,
        isTrue,
      );
      expect(
        const ScmDiffIdentity('/r/a.dart', ScmDiffMode.staged)
            .isWritableWorkingTree,
        isFalse,
      );
      expect(
        const ScmDiffIdentity('/r/a.dart', ScmDiffMode.changes)
            .isWritableWorkingTree,
        isFalse,
      );
    });

    test('equality is by path and mode', () {
      expect(
        const ScmDiffIdentity('/r/a.dart', ScmDiffMode.staged),
        const ScmDiffIdentity('/r/a.dart', ScmDiffMode.staged),
      );
      expect(
        const ScmDiffIdentity('/r/a.dart', ScmDiffMode.staged),
        isNot(const ScmDiffIdentity('/r/a.dart', ScmDiffMode.unstaged)),
      );
    });
  });

  group('CompareDiffIdentity', () {
    test('storage key encodes repo root and both sides', () {
      const identity = CompareDiffIdentity(
        absolutePath: '/r/a.dart',
        repoRoot: '/r',
        left: GitCompareRef('main'),
        right: GitCompareWorkingTree(),
      );
      expect(identity.storageKey, '/r/a.dart::compare:/r|ref:main|wt');
      expect(identity.isWritableWorkingTree, isFalse);
    });

    test('differing sides produce differing keys', () {
      const left = CompareDiffIdentity(
        absolutePath: '/r/a.dart',
        repoRoot: '/r',
        left: GitCompareRef('main'),
        right: GitCompareWorkingTree(),
      );
      const right = CompareDiffIdentity(
        absolutePath: '/r/a.dart',
        repoRoot: '/r',
        left: GitCompareRef('dev'),
        right: GitCompareWorkingTree(),
      );
      expect(left.storageKey, isNot(right.storageKey));
    });
  });

  group('parseDiffStorageKey', () {
    test('round trips scm identities', () {
      for (final mode in ScmDiffMode.values) {
        final identity = ScmDiffIdentity('/r/a.dart', mode);
        expect(
          DiffIdentity.parseStorageKey(identity.storageKey),
          identity,
        );
      }
    });

    test('round trips compare identities', () {
      const identity = CompareDiffIdentity(
        absolutePath: '/r/pkg/a.dart',
        repoRoot: '/r',
        left: GitCompareRef('9f1c2ab'),
        right: GitCompareWorkingTree(),
      );
      expect(DiffIdentity.parseStorageKey(identity.storageKey), identity);
    });

    test('returns null for keys that are not diff storage keys', () {
      expect(DiffIdentity.parseStorageKey('/r/a.dart'), isNull);
      expect(DiffIdentity.parseStorageKey('/r/a.dart::scm.bogus'), isNull);
      expect(DiffIdentity.parseStorageKey('/r/a.dart::compare:/r|wt'), isNull);
      expect(DiffIdentity.parseStorageKey(''), isNull);
    });

    test('WorkbenchTabId exposes the same parser', () {
      const identity = ScmDiffIdentity('/r/a.dart', ScmDiffMode.unstaged);
      expect(
        WorkbenchTabId.parseDiffStorageKey(identity.storageKey),
        identity,
      );
    });
  });

  group('WorkbenchTabId.diff', () {
    test('scm and compare identities do not collide', () {
      const scm = ScmDiffIdentity('/r/a.dart', ScmDiffMode.changes);
      const cmp = CompareDiffIdentity(
        absolutePath: '/r/a.dart',
        repoRoot: '/r',
        left: GitCompareRef('main'),
        right: GitCompareWorkingTree(),
      );
      expect(scm.storageKey, isNot(cmp.storageKey));
      expect(WorkbenchTabId.diff(scm).id, scm.storageKey);
      expect(WorkbenchTabId.diff(cmp).id, cmp.storageKey);
      expect(WorkbenchTabId.diff(scm), isNot(WorkbenchTabId.diff(cmp)));
    });

    test('diffStaged / diffChanges build scm identities', () {
      expect(
        WorkbenchTabId.diffStaged('/r/a.dart', staged: true).diffIdentity,
        const ScmDiffIdentity('/r/a.dart', ScmDiffMode.staged),
      );
      expect(
        WorkbenchTabId.diffStaged('/r/a.dart', staged: false).diffIdentity,
        const ScmDiffIdentity('/r/a.dart', ScmDiffMode.unstaged),
      );
      expect(
        WorkbenchTabId.diffChanges('/r/a.dart').diffIdentity,
        const ScmDiffIdentity('/r/a.dart', ScmDiffMode.changes),
      );
    });

    test('exposes absolute path and staged flag for diff tabs', () {
      final staged = WorkbenchTabId.diffStaged('/r/a.dart', staged: true);
      expect(staged.diffAbsolutePath, '/r/a.dart');
      expect(staged.diffStaged, isTrue);
      expect(
        WorkbenchTabId.diffStaged('/r/a.dart', staged: false).diffStaged,
        isFalse,
      );
      expect(WorkbenchTabId.diffChanges('/r/a.dart').diffStaged, isNull);
    });

    test('non-diff tabs expose no diff identity', () {
      final file = WorkbenchTabId.file('/r/a.dart');
      expect(file.diffIdentity, isNull);
      expect(file.diffAbsolutePath, isNull);
      expect(file.diffStaged, isNull);
    });
  });
}
