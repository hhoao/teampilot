import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/layout_preferences.dart';
import 'package:teampilot/services/workspace/workspace_pane_policy.dart';

void main() {
  const prefs = LayoutPreferences(
    sidebarVisible: true,
    rightToolsVisible: true,
  );

  test('wide docks all intent-visible panes', () {
    final e = WorkspacePanePolicy.effective(
      preferences: prefs,
      viewportWidth: 1200,
    );
    expect(e.isNarrow, isFalse);
    expect(e.dockLeft, isTrue);
    expect(e.dockRight, isTrue);
    expect(e.overlayLeft, isFalse);
    expect(e.overlayRight, isFalse);
  });

  test('narrow undocks sides; left/right overlays from prefs', () {
    final e = WorkspacePanePolicy.effective(
      preferences: prefs,
      viewportWidth: 700,
    );
    expect(e.isNarrow, isTrue);
    expect(e.dockLeft, isFalse);
    expect(e.dockRight, isFalse);
    expect(e.overlayLeft, isTrue);
    expect(e.overlayRight, isTrue);
  });

  test('narrow + hidden intent → no overlay eligibility', () {
    final e = WorkspacePanePolicy.effective(
      preferences: prefs.copyWith(
        sidebarVisible: false,
        rightToolsVisible: false,
      ),
      viewportWidth: 700,
    );
    expect(e.overlayLeft, isFalse);
    expect(e.overlayRight, isFalse);
  });

  test('compose landing defaults right hidden even when prefs visible', () {
    final e = WorkspacePanePolicy.effective(
      preferences: prefs,
      viewportWidth: 1200,
      composeLanding: true,
    );
    expect(e.dockRight, isFalse);
    expect(e.dockLeft, isTrue);
  });

  test('compose landing + override true docks right', () {
    final e = WorkspacePanePolicy.effective(
      preferences: prefs,
      viewportWidth: 1200,
      composeLanding: true,
      landingRightToolsOverride: true,
    );
    expect(e.dockRight, isTrue);
  });

  test('session ignores landing override', () {
    final e = WorkspacePanePolicy.effective(
      preferences: prefs.copyWith(rightToolsVisible: false),
      viewportWidth: 1200,
      composeLanding: false,
      landingRightToolsOverride: true,
    );
    expect(e.dockRight, isFalse);
  });

  test('narrow compose + override null → no right overlay', () {
    final e = WorkspacePanePolicy.effective(
      preferences: prefs,
      viewportWidth: 700,
      composeLanding: true,
    );
    expect(e.isNarrow, isTrue);
    expect(e.dockRight, isFalse);
    expect(e.overlayRight, isFalse);
  });

  test('narrow compose + override true → overlayRight', () {
    final e = WorkspacePanePolicy.effective(
      preferences: prefs,
      viewportWidth: 700,
      composeLanding: true,
      landingRightToolsOverride: true,
    );
    expect(e.overlayRight, isTrue);
  });
}
