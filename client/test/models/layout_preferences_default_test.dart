import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/layout_preferences.dart';
import 'package:tp_markdown/tp_markdown.dart' show ContentDisplayMode;

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

  test('rightToolsVisible defaults false and round-trips', () {
    expect(const LayoutPreferences().rightToolsVisible, isFalse);
    expect(LayoutPreferences.fromJson(const {}).rightToolsVisible, isFalse);
    final parsed = LayoutPreferences.fromJson(const {
      'rightToolsVisible': true,
    });
    expect(parsed.rightToolsVisible, isTrue);
    expect(parsed.toJson()['rightToolsVisible'], isTrue);
    final restored = LayoutPreferences.fromJson(
      const LayoutPreferences(rightToolsVisible: true).toJson(),
    );
    expect(restored.rightToolsVisible, isTrue);
  });

  test('sessionTabBarVisible defaults true and round-trips', () {
    expect(const LayoutPreferences().sessionTabBarVisible, isTrue);
    expect(LayoutPreferences.fromJson(const {}).sessionTabBarVisible, isTrue);
    final parsed = LayoutPreferences.fromJson(const {
      'sessionTabBarVisible': false,
    });
    expect(parsed.sessionTabBarVisible, isFalse);
    expect(parsed.toJson()['sessionTabBarVisible'], isFalse);
    final restored = LayoutPreferences.fromJson(
      const LayoutPreferences(sessionTabBarVisible: false).toJson(),
    );
    expect(restored.sessionTabBarVisible, isFalse);
  });

  test('searchVisible defaults true and round-trips', () {
    expect(const LayoutPreferences().searchVisible, isTrue);
    expect(LayoutPreferences.fromJson(const {}).searchVisible, isTrue);
    final parsed = LayoutPreferences.fromJson(const {'searchVisible': false});
    expect(parsed.searchVisible, isFalse);
    expect(parsed.toJson()['searchVisible'], isFalse);
    final restored = LayoutPreferences.fromJson(
      const LayoutPreferences(searchVisible: false).toJson(),
    );
    expect(restored.searchVisible, isFalse);
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

  test('uiFontId and monoFontId default to bundled faces', () {
    expect(const LayoutPreferences().uiFontId, 'notoSansSc');
    expect(const LayoutPreferences().monoFontId, 'jetbrainsMono');
  });

  test('fromJson missing font keys → bundled; unknown → bundled', () {
    expect(LayoutPreferences.fromJson(const {}).uiFontId, 'notoSansSc');
    expect(LayoutPreferences.fromJson(const {}).monoFontId, 'jetbrainsMono');
    expect(
      LayoutPreferences.fromJson(const {'uiFontId': 'nope'}).uiFontId,
      'notoSansSc',
    );
    expect(
      LayoutPreferences.fromJson(const {'monoFontId': 'nope'}).monoFontId,
      'jetbrainsMono',
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
    expect(normalizeUiFontId('installed:'), 'notoSansSc');
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

  test('cot expand prefs default false and round-trip', () {
    expect(const LayoutPreferences().cotExpandReasoningOnOpen, isFalse);
    expect(const LayoutPreferences().cotExpandToolsOnOpen, isFalse);
    expect(
      LayoutPreferences.fromJson(const {}).cotExpandReasoningOnOpen,
      isFalse,
    );

    final parsed = LayoutPreferences.fromJson(const {
      'cotExpandReasoningOnOpen': true,
      'cotExpandToolsOnOpen': true,
    });
    expect(parsed.cotExpandReasoningOnOpen, isTrue);
    expect(parsed.cotExpandToolsOnOpen, isTrue);
    expect(parsed.toJson()['cotExpandReasoningOnOpen'], isTrue);
    expect(parsed.toJson()['cotExpandToolsOnOpen'], isTrue);
  });

  test('floating workspace geometry defaults null and round-trips', () {
    const defaults = LayoutPreferences();
    expect(defaults.floatingPanelLeft, isNull);
    expect(defaults.floatingPanelTop, isNull);
    expect(defaults.floatingPanelWidth, isNull);
    expect(defaults.floatingPanelHeight, isNull);
    expect(defaults.floatingToggleDx, isNull);
    expect(defaults.floatingToggleDy, isNull);
    expect(defaults.floatingMaximized, isFalse);

    const prefs = LayoutPreferences(
      floatingPanelLeft: 80,
      floatingPanelTop: 90,
      floatingPanelWidth: 720,
      floatingPanelHeight: 480,
      floatingToggleDx: -24,
      floatingToggleDy: -32,
      floatingMaximized: true,
    );
    final parsed = LayoutPreferences.fromJson(prefs.toJson());
    expect(parsed.floatingPanelLeft, 80);
    expect(parsed.floatingPanelTop, 90);
    expect(parsed.floatingPanelWidth, 720);
    expect(parsed.floatingPanelHeight, 480);
    expect(parsed.floatingToggleDx, -24);
    expect(parsed.floatingToggleDy, -32);
    expect(parsed.floatingMaximized, isTrue);
  });

  test('markdownOpenMode defaults to preview and round-trips', () {
    expect(
      const LayoutPreferences().markdownOpenMode,
      MarkdownOpenMode.preview,
    );
    expect(
      LayoutPreferences.fromJson(const {}).markdownOpenMode,
      MarkdownOpenMode.preview,
    );
    expect(
      LayoutPreferences.fromJson(const {
        'markdownOpenMode': 'source',
      }).markdownOpenMode,
      MarkdownOpenMode.source,
    );
    final remember = const LayoutPreferences().copyWith(
      markdownOpenMode: MarkdownOpenMode.remember,
    );
    expect(
      LayoutPreferences.fromJson(remember.toJson()).markdownOpenMode,
      MarkdownOpenMode.remember,
    );
    expect(
      LayoutPreferences.fromJson(const {
        'markdownOpenMode': 'nope',
      }).markdownOpenMode,
      MarkdownOpenMode.preview,
    );
  });

  test('content display modes default foldFixedHeight and round-trip', () {
    final defaults = LayoutPreferences.fromJson(const {});
    expect(defaults.chatUserMessageMode, ContentDisplayMode.foldFixedHeight);
    expect(defaults.chatCodeBlockMode, ContentDisplayMode.foldFixedHeight);
    expect(defaults.fileCodeBlockMode, ContentDisplayMode.foldFixedHeight);

    final set = const LayoutPreferences().copyWith(
      chatUserMessageMode: ContentDisplayMode.flatten,
      chatCodeBlockMode: ContentDisplayMode.foldExpandFull,
      fileCodeBlockMode: ContentDisplayMode.flatten,
    );
    final round = LayoutPreferences.fromJson(set.toJson());
    expect(round.chatUserMessageMode, ContentDisplayMode.flatten);
    expect(round.chatCodeBlockMode, ContentDisplayMode.foldExpandFull);
    expect(round.fileCodeBlockMode, ContentDisplayMode.flatten);

    expect(
      LayoutPreferences.fromJson(const {
        'chatUserMessageMode': 'nope',
      }).chatUserMessageMode,
      ContentDisplayMode.foldFixedHeight,
    );
  });

  test('foldToolCallCategories defaults to workhorse set', () {
    final prefs = const LayoutPreferences();
    expect(
      prefs.foldToolCallCategories,
      LayoutPreferences.defaultFoldToolCallCategories,
    );
    expect(
      prefs.foldToolCallCategories.contains(AiToolCallCategory.read),
      isTrue,
    );
    for (final visible in [
      AiToolCallCategory.subagent,
      AiToolCallCategory.askUser,
      AiToolCallCategory.plan,
      AiToolCallCategory.task,
    ]) {
      expect(prefs.foldToolCallCategories.contains(visible), isFalse);
    }
  });

  test('foldToolCallCategories round-trips via JSON names', () {
    final prefs = const LayoutPreferences().copyWith(
      foldToolCallCategories: {
        AiToolCallCategory.command,
        AiToolCallCategory.mcp,
      },
    );
    final parsed = LayoutPreferences.fromJson(prefs.toJson());
    expect(parsed.foldToolCallCategories, {
      AiToolCallCategory.command,
      AiToolCallCategory.mcp,
    });
  });

  test('foldToolCallCategories missing key → default; empty list → empty', () {
    expect(
      LayoutPreferences.fromJson(const {}).foldToolCallCategories,
      LayoutPreferences.defaultFoldToolCallCategories,
    );
    expect(
      LayoutPreferences.fromJson(const {
        'foldToolCallCategories': <String>[],
      }).foldToolCallCategories,
      isEmpty,
    );
  });

  test('legacy factory fold set migrates task/todos to visible', () {
    final names = LayoutPreferences.legacyFactoryFoldToolCallCategories
        .map((c) => c.name)
        .toList();
    expect(
      LayoutPreferences.fromJson({
        'foldToolCallCategories': names,
      }).foldToolCallCategories,
      LayoutPreferences.defaultFoldToolCallCategories,
    );
    expect(
      LayoutPreferences.fromJson({
        'foldToolCallCategories': [...names, 'subagent'],
      }).foldToolCallCategories.contains(AiToolCallCategory.task),
      isTrue,
    );
  });

  test('autoOpenSubagentPreview defaults false and round-trips', () {
    expect(const LayoutPreferences().autoOpenSubagentPreview, isFalse);
    expect(
      LayoutPreferences.fromJson(const {}).autoOpenSubagentPreview,
      isFalse,
    );
    final parsed = LayoutPreferences.fromJson(const {
      'autoOpenSubagentPreview': true,
    });
    expect(parsed.autoOpenSubagentPreview, isTrue);
    expect(parsed.toJson()['autoOpenSubagentPreview'], isTrue);
    final restored = LayoutPreferences.fromJson(
      const LayoutPreferences(autoOpenSubagentPreview: true).toJson(),
    );
    expect(restored.autoOpenSubagentPreview, isTrue);
  });
}
