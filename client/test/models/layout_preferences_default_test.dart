import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/layout_preferences.dart';

void main() {
  test('fromJson ignores legacy tool layout keys', () {
    final prefs = LayoutPreferences.fromJson(const {
      'toolPlacement': 'bottom',
      'toolsArrangement': 'stacked',
      'bottomToolsHeight': 300,
      'membersSplit': 0.5,
    });
    expect(prefs.rightToolsWidth, LayoutPreferences.defaultRightToolsWidth);
    expect(prefs.membersVisible, isTrue);
    expect(prefs.fileTreeVisible, isTrue);
  });

  test('sidebarVisible defaults true and round-trips', () {
    expect(const LayoutPreferences().sidebarVisible, isTrue);
    final parsed = LayoutPreferences.fromJson(const {'sidebarVisible': false});
    expect(parsed.sidebarVisible, isFalse);
    expect(parsed.toJson()['sidebarVisible'], isFalse);
  });

  test('locale defaults to system (empty) and maps dropdown values', () {
    expect(const LayoutPreferences().locale, isEmpty);
    expect(languagePreferenceUiValue(''), 'system');
    expect(languagePreferenceUiValue('en'), 'en');
    expect(languagePreferenceUiValue('zh'), 'zh');
    expect(languagePreferenceUiValue('zh_CN'), 'zh');
    expect(languagePreferenceStoredLocale('system'), isEmpty);
    expect(languagePreferenceStoredLocale('en'), 'en');
    expect(languagePreferenceStoredLocale('zh'), 'zh');
  });

  test('workspace panes keep large sizes and only clamp mins', () {
    final prefs = LayoutPreferences.fromJson(const {
      'sidebarWidth': 900,
      'rightToolsWidth': 800,
      'workspaceTerminalHeight': 700,
    });
    expect(prefs.sidebarWidth, 900);
    expect(prefs.rightToolsWidth, 800);
    expect(prefs.workspaceTerminalHeight, 700);

    final clamped = const LayoutPreferences().copyWith(
      sidebarWidth: 10,
      rightToolsWidth: 10,
      workspaceTerminalHeight: 10,
    );
    expect(clamped.sidebarWidth, LayoutPreferences.minSidebarWidth);
    expect(clamped.rightToolsWidth, LayoutPreferences.minRightToolsWidth);
    expect(
      clamped.workspaceTerminalHeight,
      LayoutPreferences.minWorkspaceTerminalHeight,
    );
  });

  test('uiFontId and monoFontId default to system', () {
    expect(const LayoutPreferences().uiFontId, 'system');
    expect(const LayoutPreferences().monoFontId, 'system');
  });

  test('fromJson missing font keys → system; unknown → system', () {
    expect(LayoutPreferences.fromJson(const {}).uiFontId, 'system');
    expect(
      LayoutPreferences.fromJson(const {'uiFontId': 'nope'}).uiFontId,
      'system',
    );
  });

  test('font ids round-trip when known', () {
    final prefs = const LayoutPreferences().copyWith(
      uiFontId: 'notoSansSc',
      monoFontId: 'jetbrainsMono',
    );
    final json = prefs.toJson();
    final parsed = LayoutPreferences.fromJson(json);
    expect(parsed.uiFontId, 'notoSansSc');
    expect(parsed.monoFontId, 'jetbrainsMono');
  });

  test('installed font ids normalize and round-trip', () {
    expect(normalizeUiFontId('installed:Foo'), 'installed:Foo');
    expect(normalizeUiFontId('installed:'), 'system');
    final prefs = const LayoutPreferences().copyWith(
      uiFontId: 'installed:NotoSansCJK-Regular',
      monoFontId: 'installed:JetBrainsMonoNL-Regular',
    );
    final parsed = LayoutPreferences.fromJson(prefs.toJson());
    expect(parsed.uiFontId, 'installed:NotoSansCJK-Regular');
    expect(parsed.monoFontId, 'installed:JetBrainsMonoNL-Regular');
  });

  test('homeSidebarWidth defaults, clamps min, keeps large', () {
    expect(
      const LayoutPreferences().homeSidebarWidth,
      LayoutPreferences.defaultHomeSidebarWidth,
    );
    expect(
      LayoutPreferences.fromJson(const {}).homeSidebarWidth,
      LayoutPreferences.defaultHomeSidebarWidth,
    );
    expect(
      LayoutPreferences.fromJson(const {
        'homeSidebarWidth': 'x',
      }).homeSidebarWidth,
      LayoutPreferences.defaultHomeSidebarWidth,
    );
    expect(
      LayoutPreferences.fromJson(const {
        'homeSidebarWidth': 10,
      }).homeSidebarWidth,
      LayoutPreferences.minHomeSidebarWidth,
    );
    expect(
      LayoutPreferences.fromJson(const {
        'homeSidebarWidth': 900,
      }).homeSidebarWidth,
      900,
    );
    final clamped = const LayoutPreferences().copyWith(homeSidebarWidth: 10);
    expect(clamped.homeSidebarWidth, LayoutPreferences.minHomeSidebarWidth);
    final roundTrip = LayoutPreferences.fromJson(
      const LayoutPreferences(homeSidebarWidth: 500).toJson(),
    );
    expect(roundTrip.homeSidebarWidth, 500);
  });
}
