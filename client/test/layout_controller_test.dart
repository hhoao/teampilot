import 'package:flashskyai_client/controllers/layout_controller.dart';
import 'package:flashskyai_client/models/layout_preferences.dart';
import 'package:flashskyai_client/repositories/layout_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('uses workbench defaults when no preferences are saved', () async {
    final repository = LayoutRepository(await SharedPreferences.getInstance());
    final controller = LayoutController(repository: repository);

    await controller.load();

    expect(controller.preferences.preset, LayoutPreset.workbench);
    expect(controller.preferences.toolPlacement, ToolPanelPlacement.right);
    expect(controller.preferences.toolsArrangement, ToolsArrangement.stacked);
    expect(controller.preferences.appRailVisible, isTrue);
    expect(controller.preferences.contextSidebarVisible, isTrue);
    expect(controller.preferences.membersVisible, isTrue);
    expect(controller.preferences.fileTreeVisible, isTrue);
    expect(controller.preferences.rightToolsWidth, 320);
  });

  test('saves and loads preferences', () async {
    final preferences = await SharedPreferences.getInstance();
    final repository = LayoutRepository(preferences);
    final controller = LayoutController(repository: repository);
    await controller.load();

    await controller.setToolPlacement(ToolPanelPlacement.bottom);
    await controller.setToolsArrangement(ToolsArrangement.tabs);
    await controller.setRegionVisibility(
      appRailVisible: false,
      contextSidebarVisible: false,
      membersVisible: true,
      fileTreeVisible: false,
    );
    await controller.setRightToolsWidth(420);

    final reloaded = LayoutController(
      repository: LayoutRepository(preferences),
    );
    await reloaded.load();

    expect(reloaded.preferences.toolPlacement, ToolPanelPlacement.bottom);
    expect(reloaded.preferences.toolsArrangement, ToolsArrangement.tabs);
    expect(reloaded.preferences.appRailVisible, isFalse);
    expect(reloaded.preferences.contextSidebarVisible, isFalse);
    expect(reloaded.preferences.membersVisible, isTrue);
    expect(reloaded.preferences.fileTreeVisible, isFalse);
    expect(reloaded.preferences.rightToolsWidth, 420);
  });

  test('clamps dragged tool panel width', () async {
    final repository = LayoutRepository(await SharedPreferences.getInstance());
    final controller = LayoutController(repository: repository);
    await controller.load();

    await controller.setRightToolsWidth(100);
    expect(controller.preferences.rightToolsWidth, 240);

    await controller.setRightToolsWidth(900);
    expect(controller.preferences.rightToolsWidth, 520);
  });

  test('hiding both tools keeps members visible', () async {
    final repository = LayoutRepository(await SharedPreferences.getInstance());
    final controller = LayoutController(repository: repository);
    await controller.load();

    await controller.setRegionVisibility(
      appRailVisible: true,
      contextSidebarVisible: true,
      membersVisible: false,
      fileTreeVisible: false,
    );

    expect(controller.preferences.membersVisible, isTrue);
    expect(controller.preferences.fileTreeVisible, isFalse);
  });
}
