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
    expect(snapshot.overlayLeft, isFalse);
    expect(snapshot.overlayRight, isFalse);
  });

  test('sizes always come from preferences regardless of dock state', () {
    const prefs = LayoutPreferences(
      sidebarWidth: 300,
      rightToolsWidth: 400,
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
  });

  test('intent fields mirror preferences even when narrow hides docking', () {
    const prefs = LayoutPreferences(
      sidebarVisible: false,
      rightToolsVisible: true,
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
    expect(snapshot.overlayLeft, isFalse);
    expect(snapshot.overlayRight, isTrue);
  });

  group('WorkspaceIdePaneBounds', () {
    test('leaves room for the main workbench beside both side panes', () {
      final bounds = WorkspaceIdePaneBounds.compute(
        availableWidth: 1000,
        dockLeft: true,
        dockRight: true,
        sidebarWidth: 260,
        rightToolsWidth: 320,
      );
      // 1000 - 320 - 320 - 2 = 358
      expect(bounds.leftMax, 1000 - 320 - 320 - 2);
      // 1000 - 260 - 320 - 2 = 418
      expect(bounds.rightMax, 1000 - 260 - 320 - 2);
      expect(
        bounds.leftMax,
        greaterThanOrEqualTo(LayoutPreferences.minSidebarWidth),
      );
    });

    test('ignores undocked opposite pane when computing side max', () {
      final bounds = WorkspaceIdePaneBounds.compute(
        availableWidth: 1000,
        dockLeft: true,
        dockRight: false,
        sidebarWidth: 260,
        rightToolsWidth: 900,
      );
      // Only one row resizer; right width ignored while undocked.
      expect(
        bounds.leftMax,
        1000 - LayoutPreferences.minWorkbenchMainWidth - 1,
      );
    });
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
      drag.start(WorkspaceIdeDragTarget.sidebar);
      drag.update(200);
      drag.end();
      expect(drag.isDragging, isFalse);
      expect(drag.end(), isNull);
    });
  });
}
