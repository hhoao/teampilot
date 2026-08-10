import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/workbench/workbench_cubit.dart';
import 'package:teampilot/cubits/workbench/workbench_tab.dart';
import 'package:teampilot/models/floating_workspace_tab.dart';
import 'package:teampilot/services/floating_workspace/close_floating_tab.dart';
import 'package:teampilot/services/floating_workspace/floating_surface.dart';
import 'package:teampilot/services/floating_workspace/floating_surface_registry.dart';

void main() {
  test('closeFloatingTab removes tab after canClose and onTabClosed', () async {
    final workbench = WorkbenchCubit();
    addTearDown(workbench.close);

    var closed = false;
    final surface = _FakeSurface(
      id: 'terminal',
      onClosed: () => closed = true,
    );
    final registry = FloatingSurfaceRegistry([surface]);

    const tab = FloatingTab(
      id: 'shell:a',
      surfaceId: 'terminal',
      title: 'Terminal',
      payload: 'a',
    );
    workbench.openFloating('ws-1', WorkbenchTabId.shell('a'));

    await closeFloatingTab(
      workbench: workbench,
      workspaceId: 'ws-1',
      registry: registry,
      id: WorkbenchTabId.shell('a'),
      tab: tab,
    );

    expect(closed, isTrue);
    expect(workbench.state.bar('ws-1').floating.order, isEmpty);
  });

  test('closeFloatingTab aborts when canClose returns false', () async {
    final workbench = WorkbenchCubit();
    addTearDown(workbench.close);

    var closed = false;
    final surface = _FakeSurface(
      id: 'filePreview',
      allowClose: false,
      onClosed: () => closed = true,
    );
    final registry = FloatingSurfaceRegistry([surface]);

    const tab = FloatingTab(
      id: 'file:/a.txt',
      surfaceId: 'filePreview',
      title: 'a.txt',
      payload: '/a.txt',
    );
    workbench.openFloating('ws-1', WorkbenchTabId.file('/a.txt'));

    await closeFloatingTab(
      workbench: workbench,
      workspaceId: 'ws-1',
      registry: registry,
      id: WorkbenchTabId.file('/a.txt'),
      tab: tab,
    );

    expect(closed, isFalse);
    expect(
      workbench.state.bar('ws-1').floating.order,
      [WorkbenchTabId.file('/a.txt')],
    );
  });

  test('closeFloatingTab removes unknown surface tab without callback', () async {
    final workbench = WorkbenchCubit();
    addTearDown(workbench.close);
    final registry = FloatingSurfaceRegistry([]);

    const tab = FloatingTab(
      id: 'orphan',
      surfaceId: 'missing',
      title: 'Orphan',
    );
    workbench.openFloating('ws-1', WorkbenchTabId.shell('orphan'));

    await closeFloatingTab(
      workbench: workbench,
      workspaceId: 'ws-1',
      registry: registry,
      id: WorkbenchTabId.shell('orphan'),
      tab: tab,
    );

    expect(workbench.state.bar('ws-1').floating.order, isEmpty);
  });

  test('closeOtherFloatingTabs keeps only the requested tab', () async {
    final workbench = WorkbenchCubit();
    addTearDown(workbench.close);
    final registry = FloatingSurfaceRegistry([
      _FakeSurface(id: 'terminal', onClosed: () {}),
    ]);

    workbench.openFloating('ws-1', WorkbenchTabId.shell('keep'));
    workbench.openFloating('ws-1', WorkbenchTabId.shell('other'));

    await closeOtherFloatingTabs(
      workbench: workbench,
      workspaceId: 'ws-1',
      registry: registry,
      keepId: WorkbenchTabId.shell('keep'),
    );

    expect(
      workbench.state.bar('ws-1').floating.order,
      [WorkbenchTabId.shell('keep')],
    );
  });

  test('closeFloatingTabsToTheRight trims after the pivot', () async {
    final workbench = WorkbenchCubit();
    addTearDown(workbench.close);
    final registry = FloatingSurfaceRegistry([
      _FakeSurface(id: 'terminal', onClosed: () {}),
    ]);

    workbench.openFloating('ws-1', WorkbenchTabId.shell('a'));
    workbench.openFloating('ws-1', WorkbenchTabId.shell('b'));
    workbench.openFloating('ws-1', WorkbenchTabId.shell('c'));

    await closeFloatingTabsToTheRight(
      workbench: workbench,
      workspaceId: 'ws-1',
      registry: registry,
      fromId: WorkbenchTabId.shell('a'),
    );

    expect(
      workbench.state.bar('ws-1').floating.order,
      [WorkbenchTabId.shell('a')],
    );
  });
}

class _FakeSurface extends FloatingSurface {
  _FakeSurface({
    required this.id,
    this.allowClose = true,
    required this.onClosed,
  });

  @override
  final String id;

  final bool allowClose;
  final VoidCallback onClosed;

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
  FloatingTab createTab({required String workspaceId, Object? payload}) {
    return FloatingTab(
      id: 'fake:$workspaceId',
      surfaceId: id,
      title: 'fake',
      payload: payload,
    );
  }

  @override
  Future<bool> canClose(FloatingTab tab, {BuildContext? context}) async =>
      allowClose;

  @override
  void onTabClosed(FloatingTab tab) => onClosed();
}
