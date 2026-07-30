import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/floating_workspace/floating_workspace_cubit.dart';
import 'package:teampilot/models/floating_workspace_tab.dart';
import 'package:teampilot/services/floating_workspace/close_floating_tab.dart';
import 'package:teampilot/services/floating_workspace/floating_surface.dart';
import 'package:teampilot/services/floating_workspace/floating_surface_registry.dart';

void main() {
  test('closeFloatingTab removes tab after canClose and onTabClosed', () async {
    final cubit = FloatingWorkspaceCubit();
    addTearDown(cubit.close);

    var closed = false;
    final surface = _FakeSurface(
      id: 'terminal',
      onClosed: () => closed = true,
    );
    final registry = FloatingSurfaceRegistry([surface]);

    cubit.setActiveWorkspace('ws-1');
    const tab = FloatingTab(
      id: 'shell:a',
      surfaceId: 'terminal',
      title: 'Terminal',
      payload: 'a',
    );
    cubit.ensureTab(tab);

    await closeFloatingTab(cubit: cubit, registry: registry, tab: tab);

    expect(closed, isTrue);
    expect(cubit.state.activeBucket.tabs, isEmpty);
  });

  test('closeFloatingTab aborts when canClose returns false', () async {
    final cubit = FloatingWorkspaceCubit();
    addTearDown(cubit.close);

    var closed = false;
    final surface = _FakeSurface(
      id: 'filePreview',
      allowClose: false,
      onClosed: () => closed = true,
    );
    final registry = FloatingSurfaceRegistry([surface]);

    cubit.setActiveWorkspace('ws-1');
    const tab = FloatingTab(
      id: 'file:/a.txt',
      surfaceId: 'filePreview',
      title: 'a.txt',
      payload: '/a.txt',
    );
    cubit.ensureTab(tab);

    await closeFloatingTab(cubit: cubit, registry: registry, tab: tab);

    expect(closed, isFalse);
    expect(cubit.state.activeBucket.tabs.single.id, tab.id);
  });

  test('closeFloatingTab removes unknown surface tab without callback', () async {
    final cubit = FloatingWorkspaceCubit();
    addTearDown(cubit.close);
    final registry = FloatingSurfaceRegistry([]);

    cubit.setActiveWorkspace('ws-1');
    const tab = FloatingTab(
      id: 'orphan',
      surfaceId: 'missing',
      title: 'Orphan',
    );
    cubit.ensureTab(tab);

    await closeFloatingTab(cubit: cubit, registry: registry, tab: tab);

    expect(cubit.state.activeBucket.tabs, isEmpty);
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
