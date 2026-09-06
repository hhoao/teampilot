import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/workbench/workbench_cubit.dart';
import 'package:teampilot/cubits/workbench/workbench_tab.dart';
import 'package:teampilot/models/floating_workspace_tab.dart';
import 'package:teampilot/services/floating_workspace/close_floating_tab.dart';
import 'package:teampilot/services/floating_workspace/floating_surface.dart';
import 'package:teampilot/services/floating_workspace/floating_surface_registry.dart';

class _FakeSurface extends FloatingSurface {
  _FakeSurface(this.id);

  @override
  final String id;

  @override
  FloatingEmptyAction? get emptyAction => null;

  @override
  bool get allowMultipleTabs => true;

  @override
  Future<void> activate(FloatingTab tab) async {}

  @override
  Widget build(BuildContext context, FloatingTab tab) =>
      const SizedBox.shrink();

  @override
  FloatingTab createTab({required String workspaceId, Object? payload}) =>
      FloatingTab(id: 'fake:$payload', surfaceId: id, title: 'fake');
}

FloatingSurfaceRegistry _registry() => FloatingSurfaceRegistry([
  _FakeSurface('terminal'),
]);

void main() {
  test('closeAllFloatingTabs keeps pinned tabs', () async {
    final workbench = WorkbenchCubit();
    addTearDown(workbench.close);
    workbench.openFloating('ws', WorkbenchTabId.shell('e1'));
    workbench.openFloating('ws', WorkbenchTabId.shell('e2'));
    workbench.pin('ws', WorkbenchTabId.shell('e2'));

    await closeAllFloatingTabs(
      workbench: workbench,
      workspaceId: 'ws',
      registry: _registry(),
    );

    expect(workbench.floatingOrder('ws'), [WorkbenchTabId.shell('e2')]);
  });

  test('closeOtherFloatingTabs and closeFloatingTabsToTheRight keep pinned',
      () async {
    final workbench = WorkbenchCubit();
    addTearDown(workbench.close);
    workbench.openFloating('ws', WorkbenchTabId.shell('e1'));
    workbench.openFloating('ws', WorkbenchTabId.shell('e2'));
    workbench.openFloating('ws', WorkbenchTabId.shell('e3'));
    workbench.pin('ws', WorkbenchTabId.shell('e3'));

    await closeOtherFloatingTabs(
      workbench: workbench,
      workspaceId: 'ws',
      registry: _registry(),
      keepId: WorkbenchTabId.shell('e1'),
    );
    expect(workbench.floatingOrder('ws'), [
      WorkbenchTabId.shell('e1'),
      WorkbenchTabId.shell('e3'),
    ]);

    await closeFloatingTabsToTheRight(
      workbench: workbench,
      workspaceId: 'ws',
      registry: _registry(),
      fromId: WorkbenchTabId.shell('e1'),
    );
    expect(workbench.floatingOrder('ws'), [
      WorkbenchTabId.shell('e1'),
      WorkbenchTabId.shell('e3'),
    ]);
  });
}
