import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/workbench/workbench_cubit.dart';
import 'package:teampilot/cubits/workbench/workbench_tab.dart';

void main() {
  group('WorkbenchCubit', () {
    late WorkbenchCubit cubit;

    setUp(() {
      cubit = WorkbenchCubit();
    });

    tearDown(() async {
      await cubit.close();
    });

    test('ensureTab appends and activates; re-open dedupes', () {
      const ws = 'ws-a';
      final session = WorkbenchTabId.session('s1');
      final file = WorkbenchTabId.file('/repo/a.dart');

      cubit.ensureTab(ws, session);
      cubit.ensureTab(ws, file);

      expect(cubit.tabOrder(ws), [session, file]);
      expect(cubit.activeTabId(ws), file);

      cubit.ensureTab(ws, session);
      expect(cubit.tabOrder(ws), [session, file]);
      expect(cubit.activeTabId(ws), session);
    });

    test('buckets are isolated per workspace', () {
      const a = 'ws-a';
      const b = 'ws-b';
      final fileA = WorkbenchTabId.file('/a.dart');
      final fileB = WorkbenchTabId.file('/b.dart');

      cubit.ensureTab(a, fileA);
      cubit.ensureTab(b, fileB);

      expect(cubit.tabOrder(a), [fileA]);
      expect(cubit.tabOrder(b), [fileB]);
      expect(cubit.activeTabId(a), fileA);
      expect(cubit.activeTabId(b), fileB);
    });

    test('removeTab activates previous neighbor', () {
      const ws = 'ws-a';
      final s1 = WorkbenchTabId.session('s1');
      final f1 = WorkbenchTabId.file('/a.dart');
      final d1 = WorkbenchTabId.diff('/a.dart', staged: false);

      cubit.ensureTab(ws, s1);
      cubit.ensureTab(ws, f1);
      cubit.ensureTab(ws, d1);
      expect(cubit.activeTabId(ws), d1);

      cubit.removeTab(ws, d1);
      expect(cubit.tabOrder(ws), [s1, f1]);
      expect(cubit.activeTabId(ws), f1);

      cubit.removeTab(ws, f1);
      expect(cubit.activeTabId(ws), s1);

      cubit.removeTab(ws, s1);
      expect(cubit.tabOrder(ws), isEmpty);
      expect(cubit.activeTabId(ws), isNull);
    });

    test('select sets active; closeOthers keeps one; closeRight trims', () {
      const ws = 'ws-a';
      final s1 = WorkbenchTabId.session('s1');
      final f1 = WorkbenchTabId.file('/a.dart');
      final f2 = WorkbenchTabId.file('/b.dart');
      final d1 = WorkbenchTabId.diff('/a.dart', staged: true);

      cubit.ensureTab(ws, s1);
      cubit.ensureTab(ws, f1);
      cubit.ensureTab(ws, f2);
      cubit.ensureTab(ws, d1);

      cubit.select(ws, f1);
      expect(cubit.activeTabId(ws), f1);

      final closedRight = cubit.closeRight(ws, f1);
      expect(closedRight, [f2, d1]);
      expect(cubit.tabOrder(ws), [s1, f1]);

      cubit.ensureTab(ws, f2);
      cubit.ensureTab(ws, d1);
      cubit.select(ws, f1);
      final closedOthers = cubit.closeOthers(ws, f1);
      expect(closedOthers, [s1, f2, d1]);
      expect(cubit.tabOrder(ws), [f1]);
      expect(cubit.activeTabId(ws), f1);
    });

    test('staged and unstaged diffs are distinct tabs', () {
      const ws = 'ws-a';
      final unstaged = WorkbenchTabId.diff('/a.dart', staged: false);
      final staged = WorkbenchTabId.diff('/a.dart', staged: true);

      cubit.ensureTab(ws, unstaged);
      cubit.ensureTab(ws, staged);

      expect(cubit.tabOrder(ws), [unstaged, staged]);
      expect(unstaged, isNot(staged));
    });

    test('syncSessions activates preferred session when not composing', () {
      const ws = 'ws-a';
      cubit.clearActive(ws);
      cubit.syncSessions(
        ws,
        ['s1', 's2'],
        preferredActiveSessionId: 's2',
        composeActive: false,
      );
      expect(cubit.tabOrder(ws), [
        WorkbenchTabId.session('s1'),
        WorkbenchTabId.session('s2'),
      ]);
      expect(cubit.activeTabId(ws), WorkbenchTabId.session('s2'));
    });

    test('syncSessions keeps active null while composing', () {
      const ws = 'ws-a';
      cubit.ensureTab(ws, WorkbenchTabId.session('s1'));
      cubit.clearActive(ws);
      cubit.syncSessions(
        ws,
        ['s1'],
        preferredActiveSessionId: 's1',
        composeActive: true,
      );
      expect(cubit.tabOrder(ws), [WorkbenchTabId.session('s1')]);
      expect(cubit.activeTabId(ws), isNull);
    });

    test('syncSessions does not steal focus from file/diff tab', () {
      const ws = 'ws-a';
      final file = WorkbenchTabId.file('/a.dart');
      cubit.ensureTab(ws, WorkbenchTabId.session('s1'));
      cubit.ensureTab(ws, file);
      cubit.syncSessions(
        ws,
        ['s1'],
        preferredActiveSessionId: 's1',
        composeActive: false,
      );
      expect(cubit.activeTabId(ws), file);
    });

    test('preview open replaces existing preview; permanent pins', () {
      const ws = 'ws-a';
      final a = WorkbenchTabId.file('/a.dart');
      final b = WorkbenchTabId.file('/b.dart');
      final c = WorkbenchTabId.file('/c.dart');

      expect(cubit.ensureTab(ws, a, preview: true), isNull);
      expect(cubit.isPreview(ws, a), isTrue);

      final replaced = cubit.ensureTab(ws, b, preview: true);
      expect(replaced, a);
      expect(cubit.tabOrder(ws), [b]);
      expect(cubit.isPreview(ws, b), isTrue);
      expect(cubit.isPreview(ws, a), isFalse);

      cubit.ensureTab(ws, b, preview: false);
      expect(cubit.isPreview(ws, b), isFalse);

      expect(cubit.ensureTab(ws, c, preview: true), isNull);
      expect(cubit.tabOrder(ws), [b, c]);
      expect(cubit.isPreview(ws, c), isTrue);
    });

    test('diff preview can replace file preview', () {
      const ws = 'ws-a';
      final file = WorkbenchTabId.file('/a.dart');
      final diff = WorkbenchTabId.diff('/a.dart', staged: false);

      cubit.ensureTab(ws, file, preview: true);
      final replaced = cubit.ensureTab(ws, diff, preview: true);
      expect(replaced, file);
      expect(cubit.tabOrder(ws), [diff]);
      expect(cubit.isPreview(ws, diff), isTrue);
    });

    test('session preview replaces file preview and vice versa', () {
      const ws = 'ws-a';
      final file = WorkbenchTabId.file('/a.dart');
      final session = WorkbenchTabId.session('s1');

      cubit.ensureTab(ws, file, preview: true);
      final replacedFile = cubit.ensureTab(ws, session, preview: true);
      expect(replacedFile, file);
      expect(cubit.tabOrder(ws), [session]);
      expect(cubit.isPreview(ws, session), isTrue);

      final other = WorkbenchTabId.file('/b.dart');
      final replacedSession = cubit.ensureTab(ws, other, preview: true);
      expect(replacedSession, session);
      expect(cubit.tabOrder(ws), [other]);
      expect(cubit.isPreview(ws, other), isTrue);
    });

    test('ensureTab preview adopts synced permanent session into preview slot',
        () {
      const ws = 'ws-a';
      final session = WorkbenchTabId.session('s1');
      final file = WorkbenchTabId.file('/a.dart');

      cubit.ensureTab(ws, session, preview: false);
      cubit.ensureTab(ws, file, preview: true);
      expect(cubit.tabOrder(ws), [session, file]);

      final replaced = cubit.ensureTab(ws, session, preview: true);
      expect(replaced, file);
      expect(cubit.tabOrder(ws), [session]);
      expect(cubit.isPreview(ws, session), isTrue);
    });

    test('pinTab clears preview flag', () {
      const ws = 'ws-a';
      final file = WorkbenchTabId.file('/a.dart');
      cubit.ensureTab(ws, file, preview: true);
      cubit.pinTab(ws, file);
      expect(cubit.isPreview(ws, file), isFalse);
    });
  });
}
