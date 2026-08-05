import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/cubits/floating_workspace/floating_workspace_cubit.dart';
import 'package:teampilot/cubits/workbench/workbench_cubit.dart';
import 'package:teampilot/cubits/workbench/workbench_tab.dart';
import 'package:teampilot/models/floating_workspace_tab.dart';
import 'package:teampilot/models/layout_preferences.dart';
import 'package:teampilot/services/floating_workspace/migrate_legacy_workbench_tabs.dart';
import 'package:teampilot/services/workbench/workbench_shell_launcher.dart';

void main() {
  test('migrateLegacyWorkbenchTabsToFloating moves file/shell and clears strip', () {
    final workbench = WorkbenchCubit();
    final floating = FloatingWorkspaceCubit();
    addTearDown(workbench.close);
    addTearDown(floating.close);

    const ws = 'ws-a';
    final session = WorkbenchTabId.session('s1');
    final file = WorkbenchTabId.file('/repo/a.txt');
    final shell = WorkbenchTabId.shell('entry-1');
    final run = WorkbenchTabId.run('r1');

    workbench.ensureTab(ws, session);
    workbench.ensureTab(ws, run);
    workbench.emit(
      workbench.state.withBucket(
        ws,
        workbench.state.bucket(ws).copyWith(
          tabOrder: [session, file, shell, run],
        ),
      ),
    );
    floating.setActiveWorkspace('other');

    final moved = migrateLegacyWorkbenchTabsToFloating(
      workbench: workbench,
      floating: floating,
    );

    expect(moved, 2);
    expect(workbench.tabOrder(ws), [session, run]);
    expect(
      floating.buckets[ws]!.tabs.map((t) => t.id).toList(),
      containsAll([
        'file:/repo/a.txt',
        floatingShellTabId('entry-1'),
      ]),
    );
    expect(
      floating.buckets[ws]!.tabs
          .firstWhere((t) => t.id == 'file:/repo/a.txt')
          .title,
      p.basename('/repo/a.txt'),
    );
    // Active workspace restored after migration.
    expect(floating.state.activeWorkspaceId, 'other');
  });

  test('migrateLegacyWorkbenchTabsToFloating is a no-op when strip is clean', () {
    final workbench = WorkbenchCubit();
    final floating = FloatingWorkspaceCubit();
    addTearDown(workbench.close);
    addTearDown(floating.close);

    workbench.ensureTab('ws', WorkbenchTabId.session('s1'));
    expect(
      migrateLegacyWorkbenchTabsToFloating(
        workbench: workbench,
        floating: floating,
      ),
      0,
    );
    expect(floating.buckets, isEmpty);
  });

  test('migrateLegacyWorkbenchTabsToFloating can leave file tabs on center', () {
    final workbench = WorkbenchCubit();
    final floating = FloatingWorkspaceCubit();
    addTearDown(workbench.close);
    addTearDown(floating.close);

    const ws = 'ws-a';
    final file = WorkbenchTabId.file('/repo/a.txt');
    final shell = WorkbenchTabId.shell('entry-1');
    workbench.emit(
      workbench.state.withBucket(
        ws,
        workbench.state.bucket(ws).copyWith(tabOrder: [file, shell]),
      ),
    );

    final moved = migrateLegacyWorkbenchTabsToFloating(
      workbench: workbench,
      floating: floating,
      migrateFiles: false,
    );

    expect(moved, 1);
    expect(workbench.tabOrder(ws), [file]);
    expect(
      floating.buckets[ws]!.tabs.map((t) => t.id).toList(),
      [floatingShellTabId('entry-1')],
    );
  });

  test('migrateFloatingFileTabsToWorkbench moves files and leaves shells', () {
    final workbench = WorkbenchCubit();
    final floating = FloatingWorkspaceCubit();
    addTearDown(workbench.close);
    addTearDown(floating.close);

    const ws = 'ws-a';
    floating.setActiveWorkspace(ws);
    floating.ensureTab(
      FloatingTab(
        id: 'file:/repo/a.txt',
        surfaceId: 'filePreview',
        title: 'a.txt',
        payload: '/repo/a.txt',
      ),
    );
    floating.ensureTab(
      FloatingTab(
        id: floatingShellTabId('entry-1'),
        surfaceId: 'terminal',
        title: 'entry-1',
        payload: 'entry-1',
      ),
    );
    floating.setActiveWorkspace('other');

    final moved = migrateFloatingFileTabsToWorkbench(
      workbench: workbench,
      floating: floating,
    );

    expect(moved, 1);
    expect(workbench.tabOrder(ws), [WorkbenchTabId.file('/repo/a.txt')]);
    expect(
      floating.buckets[ws]!.tabs.map((t) => t.id).toList(),
      [floatingShellTabId('entry-1')],
    );
    expect(floating.state.activeWorkspaceId, 'other');
  });

  test('syncFilePreviewHostTabs center moves floating files to strip', () {
    final workbench = WorkbenchCubit();
    final floating = FloatingWorkspaceCubit();
    addTearDown(workbench.close);
    addTearDown(floating.close);

    const ws = 'ws-a';
    floating.setActiveWorkspace(ws);
    floating.ensureTab(
      FloatingTab(
        id: 'file:/repo/b.txt',
        surfaceId: 'filePreview',
        title: 'b.txt',
        payload: '/repo/b.txt',
      ),
    );

    final moved = syncFilePreviewHostTabs(
      workbench: workbench,
      floating: floating,
      host: FilePreviewHost.center,
    );

    expect(moved, 1);
    expect(workbench.tabOrder(ws), [WorkbenchTabId.file('/repo/b.txt')]);
    expect(floating.buckets[ws], isNull);
  });
}
