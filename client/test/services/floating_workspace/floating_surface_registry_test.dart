import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/floating_workspace/floating_workspace_state.dart';
import 'package:teampilot/services/floating_workspace/floating_surface.dart';
import 'package:teampilot/services/floating_workspace/floating_surface_registry.dart';

void main() {
  test(
    'built-in registry empty actions are terminal, openFile, then none for minimize-only chrome',
    () {
      final registry = FloatingSurfaceRegistry.withDefaults(
        file: _FakeSurface(id: 'filePreview', emptyLabel: 'openFile'),
        terminal: _FakeSurface(id: 'terminal', emptyLabel: 'newTerminal'),
      );
      expect(
        registry.emptyActions.map((a) => a.commandId).toList(),
        ['floatingWorkspace.newTerminal', 'floatingWorkspace.openFile'],
      );
    },
  );

  test('withDefaults html surface registers preview empty action + lookup', () {
    final registry = FloatingSurfaceRegistry.withDefaults(
      file: _FakeSurface(id: 'filePreview', emptyLabel: 'openFile'),
      terminal: _FakeSurface(id: 'terminal', emptyLabel: 'newTerminal'),
      html: _FakeSurface(id: 'htmlPreview', emptyLabel: 'openHtmlPreview'),
    );
    expect(
      registry.emptyActions.map((a) => a.commandId).toList(),
      [
        'floatingWorkspace.newTerminal',
        'floatingWorkspace.openFile',
        'floatingWorkspace.openHtmlPreview',
      ],
    );
    expect(registry['htmlPreview'], isNotNull);
    expect(registry['htmlPreview']?.id, 'htmlPreview');
  });

  test('withDefaults omits html surface when not provided', () {
    final registry = FloatingSurfaceRegistry.withDefaults(
      file: _FakeSurface(id: 'filePreview', emptyLabel: 'openFile'),
      terminal: _FakeSurface(id: 'terminal', emptyLabel: 'newTerminal'),
    );
    expect(registry['htmlPreview'], isNull);
  });
}

class _FakeSurface extends FloatingSurface {
  _FakeSurface({required this.id, required String emptyLabel})
    : emptyAction = FloatingEmptyAction(
        commandId: 'floatingWorkspace.$emptyLabel',
        labelKey: emptyLabel,
        icon: Icons.circle,
      );

  @override
  final String id;

  @override
  final FloatingEmptyAction emptyAction;

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
}
