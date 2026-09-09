import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/workbench/workbench_cubit.dart';
import 'package:teampilot/cubits/workbench/workbench_tab.dart';

/// Landing (workspace start page) return-target contract: entering the
/// landing remembers the active center tab, the back control re-activates it,
/// and without a valid target the landing stays up as the start page.
void main() {
  const ws = 'workspace-1';
  final sessionA = WorkbenchTabId.session('session-a');
  final sessionB = WorkbenchTabId.session('session-b');
  final fileTab = WorkbenchTabId.file('/repo/lib/main.dart');

  late WorkbenchCubit workbench;
  setUp(() {
    workbench = WorkbenchCubit();
  });
  tearDown(() => workbench.close());

  group('enterLanding return target', () {
    test('captures the active tab', () {
      workbench.openSession(ws, sessionA.id);
      workbench.openSession(ws, sessionB.id);
      workbench.activate(ws, sessionB);

      workbench.enterLanding(ws);

      expect(workbench.centerActiveId(ws), isNull);
      expect(workbench.canExitLanding(ws), isTrue);
      expect(workbench.centerFocusedStrip(ws).landingReturnTabId, sessionB);
    });

    test('re-entering while landing keeps the target and the tab order', () {
      workbench.openSession(ws, sessionA.id);
      workbench.enterLanding(ws);
      final order = List.of(workbench.centerOrder(ws));

      workbench.enterLanding(ws);

      expect(workbench.centerActiveId(ws), isNull);
      expect(workbench.centerOrder(ws), order);
      expect(workbench.centerFocusedStrip(ws).landingReturnTabId, sessionA);
    });

    test('fresh workspace without tabs has no return target', () {
      workbench.enterLanding(ws);

      expect(workbench.centerLandingActive(ws), isTrue);
      expect(workbench.canExitLanding(ws), isFalse);
    });
  });

  group('exitLanding', () {
    test('re-activates the remembered tab and clears the target', () {
      workbench.openSession(ws, sessionA.id);
      workbench.openSession(ws, sessionB.id);
      workbench.activate(ws, sessionB);
      workbench.enterLanding(ws);

      workbench.exitLanding(ws);

      expect(workbench.centerActiveId(ws), sessionB);
      expect(workbench.centerLandingActive(ws), isFalse);
      expect(workbench.centerFocusedStrip(ws).landingReturnTabId, isNull);
    });

    test('stays on the landing without a return target', () {
      workbench.enterLanding(ws);

      workbench.exitLanding(ws);

      expect(workbench.centerLandingActive(ws), isTrue);
    });

    test('stays on the landing when the remembered tab was removed', () async {
      workbench.openSession(ws, sessionA.id);
      workbench.enterLanding(ws);

      await workbench.close(ws, sessionA);
      workbench.exitLanding(ws);

      expect(workbench.centerLandingActive(ws), isTrue);
      expect(workbench.canExitLanding(ws), isFalse);
    });

    test('exit then re-enter captures the newly active tab', () {
      workbench.openSession(ws, sessionA.id);
      workbench.openSession(ws, sessionB.id);
      workbench.activate(ws, sessionA);
      workbench.enterLanding(ws);
      workbench.exitLanding(ws);

      workbench.activate(ws, sessionB);
      workbench.enterLanding(ws);

      expect(workbench.centerFocusedStrip(ws).landingReturnTabId, sessionB);
    });

    test('opening a tab while landing exits and clears the target', () {
      workbench.openSession(ws, sessionA.id);
      workbench.enterLanding(ws);

      workbench.openFile(ws, fileTab.id);

      expect(workbench.centerActiveId(ws), fileTab);
      expect(workbench.centerFocusedStrip(ws).landingReturnTabId, isNull);

      workbench.enterLanding(ws);
      expect(workbench.centerFocusedStrip(ws).landingReturnTabId, fileTab);
    });
  });
}
