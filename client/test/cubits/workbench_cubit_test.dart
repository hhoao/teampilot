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
      final diff = WorkbenchTabId.diffStaged('/repo/a.dart', staged: false);

      cubit.ensureTab(ws, session);
      cubit.ensureTab(ws, diff);

      expect(cubit.tabOrder(ws), [session, diff]);
      expect(cubit.activeTabId(ws), diff);

      cubit.ensureTab(ws, session);
      expect(cubit.tabOrder(ws), [session, diff]);
      expect(cubit.activeTabId(ws), session);
    });

    test('reorderTabs permutes mixed kinds and keeps active', () {
      const ws = 'ws-a';
      final session = WorkbenchTabId.session('s1');
      final file = WorkbenchTabId.file('/a.dart');
      final run = WorkbenchTabId.run('r1');

      cubit.ensureTab(ws, session);
      cubit.ensureTab(ws, file);
      cubit.ensureTab(ws, run);
      expect(cubit.activeTabId(ws), run);

      cubit.reorderTabs(ws, 0, 2);
      expect(cubit.tabOrder(ws), [file, run, session]);
      expect(cubit.activeTabId(ws), run);
    });

    test('ensureTab rejects shell tabs but allows file on center strip', () {
      const ws = 'ws-a';
      final session = WorkbenchTabId.session('s1');
      cubit.ensureTab(ws, session);

      final file = WorkbenchTabId.file('/a.dart');
      cubit.ensureTab(ws, file);
      expect(cubit.tabOrder(ws), [session, file]);
      expect(cubit.activeTabId(ws), file);

      cubit.ensureTab(ws, WorkbenchTabId.shell('e1'));
      expect(cubit.tabOrder(ws), [session, file]);
      expect(cubit.activeTabId(ws), file);
    });

    test('buckets are isolated per workspace', () {
      const a = 'ws-a';
      const b = 'ws-b';
      final diffA = WorkbenchTabId.diffStaged('/a.dart', staged: false);
      final diffB = WorkbenchTabId.diffStaged('/b.dart', staged: true);

      cubit.ensureTab(a, diffA);
      cubit.ensureTab(b, diffB);

      expect(cubit.tabOrder(a), [diffA]);
      expect(cubit.tabOrder(b), [diffB]);
      expect(cubit.activeTabId(a), diffA);
      expect(cubit.activeTabId(b), diffB);
    });

    test('removeTab activates previous neighbor', () {
      const ws = 'ws-a';
      final s1 = WorkbenchTabId.session('s1');
      final d1 = WorkbenchTabId.diffStaged('/a.dart', staged: false);
      final d2 = WorkbenchTabId.diffStaged('/b.dart', staged: true);

      cubit.ensureTab(ws, s1);
      cubit.ensureTab(ws, d1);
      cubit.ensureTab(ws, d2);
      expect(cubit.activeTabId(ws), d2);

      cubit.removeTab(ws, d2);
      expect(cubit.tabOrder(ws), [s1, d1]);
      expect(cubit.activeTabId(ws), d1);

      cubit.removeTab(ws, d1);
      expect(cubit.activeTabId(ws), s1);

      cubit.removeTab(ws, s1);
      expect(cubit.tabOrder(ws), isEmpty);
      expect(cubit.activeTabId(ws), isNull);
    });

    test('select sets active; closeOthers keeps one; closeRight trims', () {
      const ws = 'ws-a';
      final s1 = WorkbenchTabId.session('s1');
      final d1 = WorkbenchTabId.diffStaged('/a.dart', staged: false);
      final d2 = WorkbenchTabId.diffStaged('/b.dart', staged: false);
      final d3 = WorkbenchTabId.diffStaged('/c.dart', staged: true);

      cubit.ensureTab(ws, s1);
      cubit.ensureTab(ws, d1);
      cubit.ensureTab(ws, d2);
      cubit.ensureTab(ws, d3);

      cubit.select(ws, d1);
      expect(cubit.activeTabId(ws), d1);

      final closedRight = cubit.closeRight(ws, d1);
      expect(closedRight, [d2, d3]);
      expect(cubit.tabOrder(ws), [s1, d1]);

      cubit.ensureTab(ws, d2);
      cubit.ensureTab(ws, d3);
      cubit.select(ws, d1);
      final closedOthers = cubit.closeOthers(ws, d1);
      expect(closedOthers, [s1, d2, d3]);
      expect(cubit.tabOrder(ws), [d1]);
      expect(cubit.activeTabId(ws), d1);
    });

    test('staged and unstaged diffs are distinct tabs', () {
      const ws = 'ws-a';
      final unstaged = WorkbenchTabId.diffStaged('/a.dart', staged: false);
      final staged = WorkbenchTabId.diffStaged('/a.dart', staged: true);

      cubit.ensureTab(ws, unstaged);
      cubit.ensureTab(ws, staged);

      expect(cubit.tabOrder(ws), [unstaged, staged]);
      expect(unstaged, isNot(staged));
    });

    test('syncSessions keeps active null while welcomeActive', () {
      const ws = 'ws-a';
      cubit.ensureTab(ws, WorkbenchTabId.session('s1'));
      cubit.enterWelcome(ws);
      cubit.syncSessions(
        ws,
        ['s1', 's2'],
        preferredActiveSessionId: 's1',
        newChatActive: false,
      );
      expect(cubit.tabOrder(ws), [
        WorkbenchTabId.session('s1'),
        WorkbenchTabId.session('s2'),
      ]);
      expect(cubit.activeTabId(ws), isNull);
      expect(cubit.welcomeActive(ws), isTrue);
    });

    test('syncSessions activates preferred session when not composing', () {
      const ws = 'ws-a';
      cubit.clearActive(ws);
      cubit.syncSessions(
        ws,
        ['s1', 's2'],
        preferredActiveSessionId: 's2',
        newChatActive: false,
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
        newChatActive: true,
      );
      expect(cubit.tabOrder(ws), [WorkbenchTabId.session('s1')]);
      expect(cubit.activeTabId(ws), isNull);
    });

    test('syncSessions does not steal focus from diff tab', () {
      const ws = 'ws-a';
      final diff = WorkbenchTabId.diffStaged('/a.dart', staged: false);
      cubit.ensureTab(ws, WorkbenchTabId.session('s1'));
      cubit.ensureTab(ws, diff);
      cubit.syncSessions(
        ws,
        ['s1'],
        preferredActiveSessionId: 's1',
        newChatActive: false,
      );
      expect(cubit.activeTabId(ws), diff);
    });

    // Landing compose unmounts ChatPage while a Run tab may stay active;
    // syncSessions alone must not focus the new session (callers ensureTab).
    test('syncSessions does not steal focus from run tab', () {
      const ws = 'ws-a';
      final run = WorkbenchTabId.run('r1');
      cubit.ensureTab(ws, run);
      cubit.syncSessions(
        ws,
        ['s-new'],
        preferredActiveSessionId: 's-new',
        newChatActive: false,
      );
      expect(cubit.activeTabId(ws), run);
      expect(cubit.tabOrder(ws), contains(WorkbenchTabId.session('s-new')));
    });

    test('ensureTab selects session over active run tab', () {
      const ws = 'ws-a';
      final run = WorkbenchTabId.run('r1');
      cubit.ensureTab(ws, run);
      cubit.ensureTab(ws, WorkbenchTabId.session('s-new'));
      expect(cubit.activeTabId(ws), WorkbenchTabId.session('s-new'));
    });

    test('preview open replaces existing preview; permanent pins', () {
      const ws = 'ws-a';
      final a = WorkbenchTabId.diffStaged('/a.dart', staged: false);
      final b = WorkbenchTabId.diffStaged('/b.dart', staged: false);
      final c = WorkbenchTabId.diffStaged('/c.dart', staged: false);

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

    test('second diff preview replaces first diff preview', () {
      const ws = 'ws-a';
      final first = WorkbenchTabId.diffStaged('/a.dart', staged: false);
      final second = WorkbenchTabId.diffStaged('/b.dart', staged: false);

      cubit.ensureTab(ws, first, preview: true);
      final replaced = cubit.ensureTab(ws, second, preview: true);
      expect(replaced, first);
      expect(cubit.tabOrder(ws), [second]);
      expect(cubit.isPreview(ws, second), isTrue);
    });

    test('session preview replaces diff preview and vice versa', () {
      const ws = 'ws-a';
      final diff = WorkbenchTabId.diffStaged('/a.dart', staged: false);
      final session = WorkbenchTabId.session('s1');

      cubit.ensureTab(ws, diff, preview: true);
      final replacedDiff = cubit.ensureTab(ws, session, preview: true);
      expect(replacedDiff, diff);
      expect(cubit.tabOrder(ws), [session]);
      expect(cubit.isPreview(ws, session), isTrue);

      final other = WorkbenchTabId.diffStaged('/b.dart', staged: false);
      final replacedSession = cubit.ensureTab(ws, other, preview: true);
      expect(replacedSession, session);
      expect(cubit.tabOrder(ws), [other]);
      expect(cubit.isPreview(ws, other), isTrue);
    });

    test(
      'ensureTab preview adopts synced permanent session into preview slot',
      () {
        const ws = 'ws-a';
        final session = WorkbenchTabId.session('s1');
        final diff = WorkbenchTabId.diffStaged('/a.dart', staged: false);

        cubit.ensureTab(ws, session, preview: false);
        cubit.ensureTab(ws, diff, preview: true);
        expect(cubit.tabOrder(ws), [session, diff]);

        final replaced = cubit.ensureTab(ws, session, preview: true);
        expect(replaced, diff);
        expect(cubit.tabOrder(ws), [session]);
        expect(cubit.isPreview(ws, session), isTrue);
      },
    );

    test('pinTab clears preview flag', () {
      const ws = 'ws-a';
      final diff = WorkbenchTabId.diffStaged('/a.dart', staged: false);
      cubit.ensureTab(ws, diff, preview: true);
      cubit.pinTab(ws, diff);
      expect(cubit.isPreview(ws, diff), isFalse);
    });

    test('shell/run factories and equality', () {
      final a = WorkbenchTabId.shell('e1');
      final b = WorkbenchTabId.shell('e1');
      final c = WorkbenchTabId.run('r1');
      expect(a, b);
      expect(a.kind, WorkbenchTabKind.shell);
      expect(c.kind, WorkbenchTabKind.run);
      expect(a, isNot(c));
    });

    test('ensureTab run ignores preview flag (never enters preview set)', () {
      const ws = 'ws';
      final session = WorkbenchTabId.session('s1');
      cubit.ensureTab(ws, session, preview: true);
      expect(cubit.isPreview(ws, session), isTrue);

      final run = WorkbenchTabId.run('r1');
      cubit.ensureTab(ws, run, preview: true);
      expect(cubit.isPreview(ws, run), isFalse);
      expect(cubit.isPreview(ws, session), isTrue); // not displaced
    });

    test('syncSessions preserves run/file tabs and drops legacy shell tabs', () {
      const ws = 'ws';
      final s1 = WorkbenchTabId.session('s1');
      final shell = WorkbenchTabId.shell('e1');
      final run = WorkbenchTabId.run('r1');
      final file = WorkbenchTabId.file('/a.dart');
      cubit.ensureTab(ws, s1);
      cubit.ensureTab(ws, run);
      cubit.emit(
        cubit.state.withBucket(
          ws,
          cubit.state.bucket(ws).copyWith(
            tabOrder: [s1, shell, run, file],
          ),
        ),
      );
      cubit.syncSessions(ws, ['s1', 's2']);
      expect(
        cubit.tabOrder(ws),
        containsAll([run, file, WorkbenchTabId.session('s2')]),
      );
      expect(cubit.tabOrder(ws), isNot(contains(shell)));
    });
  });
}
