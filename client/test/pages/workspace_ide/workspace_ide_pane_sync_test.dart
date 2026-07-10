import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/layout_preferences.dart';
import 'package:teampilot/pages/workspace_ide/workspace_ide_pane_sync.dart';
import 'package:teampilot/services/workspace/workspace_pane_policy.dart';

void main() {
  test('effective narrow docks false while prefs intent stays true', () {
    const prefs = LayoutPreferences(
      sidebarVisible: true,
      rightToolsVisible: true,
      sidebarWidth: 260,
      rightToolsWidth: 320,
      workspaceTerminalHeight: 220,
    );
    final effective = WorkspacePanePolicy.effective(
      preferences: prefs,
      viewportWidth: 700,
    );
    final snapshot = WorkspaceIdePaneSnapshot.from(
      preferences: prefs,
      effective: effective,
    );
    expect(snapshot.dockLeft, isFalse);
    expect(snapshot.intentSidebarVisible, isTrue);
    expect(snapshot.sidebarWidth, 260);
  });

  test('wide docks all intent-visible panes with no overlay', () {
    const prefs = LayoutPreferences(
      sidebarVisible: true,
      rightToolsVisible: true,
      workspaceTerminalVisible: true,
    );
    final effective = WorkspacePanePolicy.effective(
      preferences: prefs,
      viewportWidth: 1200,
    );
    final snapshot = WorkspaceIdePaneSnapshot.from(
      preferences: prefs,
      effective: effective,
    );
    expect(snapshot.isNarrow, isFalse);
    expect(snapshot.dockLeft, isTrue);
    expect(snapshot.dockRight, isTrue);
    expect(snapshot.dockBottom, isTrue);
    expect(snapshot.overlayLeft, isFalse);
    expect(snapshot.overlayRight, isFalse);
  });

  test('sizes always come from preferences regardless of dock state', () {
    const prefs = LayoutPreferences(
      sidebarWidth: 300,
      rightToolsWidth: 400,
      workspaceTerminalHeight: 260,
    );
    final effective = WorkspacePanePolicy.effective(
      preferences: prefs,
      viewportWidth: 700,
    );
    final snapshot = WorkspaceIdePaneSnapshot.from(
      preferences: prefs,
      effective: effective,
    );
    expect(snapshot.sidebarWidth, 300);
    expect(snapshot.rightToolsWidth, 400);
    expect(snapshot.workspaceTerminalHeight, 260);
  });

  test('intent fields mirror preferences even when narrow hides docking', () {
    const prefs = LayoutPreferences(
      sidebarVisible: false,
      rightToolsVisible: true,
      workspaceTerminalVisible: false,
    );
    final effective = WorkspacePanePolicy.effective(
      preferences: prefs,
      viewportWidth: 700,
    );
    final snapshot = WorkspaceIdePaneSnapshot.from(
      preferences: prefs,
      effective: effective,
    );
    expect(snapshot.intentSidebarVisible, isFalse);
    expect(snapshot.intentRightToolsVisible, isTrue);
    expect(snapshot.intentTerminalVisible, isFalse);
    expect(snapshot.overlayLeft, isFalse);
    expect(snapshot.overlayRight, isTrue);
  });

  group('WorkspaceIdePendingDrag', () {
    test('end returns null when no drag was started', () {
      final drag = WorkspaceIdePendingDrag();
      expect(drag.end(), isNull);
      expect(drag.isDragging, isFalse);
    });

    test('end returns null when started but never updated', () {
      final drag = WorkspaceIdePendingDrag();
      drag.start(WorkspaceIdeDragTarget.sidebar);
      expect(drag.isDragging, isTrue);
      expect(drag.end(), isNull);
    });

    test('end commits the latest updated value for the started target', () {
      final drag = WorkspaceIdePendingDrag();
      drag.start(WorkspaceIdeDragTarget.rightTools);
      drag.update(340);
      drag.update(360);
      final commit = drag.end();
      expect(commit, isNotNull);
      expect(commit!.target, WorkspaceIdeDragTarget.rightTools);
      expect(commit.value, 360);
    });

    test('drag state resets after end so a stale commit is not reissued', () {
      final drag = WorkspaceIdePendingDrag();
      drag.start(WorkspaceIdeDragTarget.workspaceTerminal);
      drag.update(200);
      drag.end();
      expect(drag.isDragging, isFalse);
      expect(drag.end(), isNull);
    });
  });
}
