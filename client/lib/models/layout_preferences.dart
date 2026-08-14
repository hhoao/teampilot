import 'package:ai_message_core/ai_message_core.dart';
import 'package:tp_markdown/tp_markdown.dart' show ContentDisplayMode;

import '../theme/app_theme.dart';
import '../theme/app_typography_scale.dart';
import '../theme/font_catalog.dart';

enum LayoutPreset { workbench, chatFocus, inspector }

enum WorkspaceEntryMode { home, lastWorkspace }

/// Default surface when opening a markdown file in the workbench editor.
enum MarkdownOpenMode { preview, source, remember }

/// Where file open/preview hosts: floating workspace overlay vs center strip.
enum FilePreviewHost { floating, center }

/// Dropdown value for language preference: `system` | `en` | `zh`.
String languagePreferenceUiValue(String locale) {
  if (locale.isEmpty) return 'system';
  return locale.startsWith('zh') ? 'zh' : 'en';
}

/// Persisted locale for a language dropdown value (`system` → empty).
String languagePreferenceStoredLocale(String uiValue) {
  return uiValue == 'system' ? '' : uiValue;
}

String normalizeUiFontId(String? id) {
  final raw = id ?? '';
  if (isInstalledFontId(raw)) return raw;
  return FontCatalog.isKnown(FontRole.ui, raw) ? raw : FontCatalog.defaultUiId;
}

String normalizeMonoFontId(String? id) {
  final raw = id ?? '';
  if (isInstalledFontId(raw)) return raw;
  return FontCatalog.isKnown(FontRole.mono, raw)
      ? raw
      : FontCatalog.defaultMonoId;
}

class LayoutPreferences {
  const LayoutPreferences({
    this.preset = LayoutPreset.workbench,
    this.workspaceEntryMode = WorkspaceEntryMode.home,
    this.lastOpenedWorkspaceId = '',
    this.appRailVisible = true,
    this.membersVisible = true,
    this.fileTreeVisible = true,
    this.gitVisible = true,
    this.searchVisible = true,
    this.boardVisible = true,
    this.rightToolsVisible = true,
    this.sidebarVisible = true,
    this.rightToolsWidth = defaultRightToolsWidth,
    this.sidebarWidth = defaultSidebarWidth,
    this.homeSidebarWidth = defaultHomeSidebarWidth,
    this.workspaceNavWidth = defaultWorkspaceNavWidth,
    this.themeMode = 'system',
    this.themeColorPreset = kDefaultThemeColorPreset,
    this.typographyScale = kDefaultTypographyScaleId,
    this.typographyScaleCustomMultiplier = kDefaultTypographyCustomMultiplier,
    this.uiZoomScale = kDefaultTypographyScaleId,
    this.uiZoomCustomMultiplier = kDefaultTypographyCustomMultiplier,
    this.terminalThemeMode = 'adaptive',
    this.locale = '',
    this.uiFontId = FontCatalog.defaultUiId,
    this.monoFontId = FontCatalog.defaultMonoId,
    this.workspaceTerminalVisible = false,
    this.workspaceTerminalHeight = defaultWorkspaceTerminalHeight,
    this.markdownOpenMode = MarkdownOpenMode.preview,
    this.cotExpandReasoningOnOpen = false,
    this.cotExpandToolsOnOpen = false,
    this.chatUserMessageMode = ContentDisplayMode.foldFixedHeight,
    this.chatCodeBlockMode = ContentDisplayMode.foldFixedHeight,
    this.fileCodeBlockMode = ContentDisplayMode.foldFixedHeight,
    this.floatingPanelLeft,
    this.floatingPanelTop,
    this.floatingPanelWidth,
    this.floatingPanelHeight,
    this.floatingPanelRightInset,
    this.floatingPanelBottomInset,
    this.floatingToggleDx,
    this.floatingToggleDy,
    this.floatingMaximized = false,
    this.filePreviewHost = FilePreviewHost.floating,
    this.foldToolCallCategories = defaultFoldToolCallCategories,
  });

  factory LayoutPreferences.fromJson(Map<String, Object?> json) {
    return LayoutPreferences(
      preset:
          _enumValue(LayoutPreset.values, json['preset']) ??
          LayoutPreset.workbench,
      workspaceEntryMode: _workspaceEntryModeFromJson(
        json['workspaceEntryMode'] as String?,
      ),
      lastOpenedWorkspaceId: json['lastOpenedWorkspaceId'] as String? ?? '',
      appRailVisible: json['appRailVisible'] as bool? ?? true,
      membersVisible: json['membersVisible'] as bool? ?? true,
      fileTreeVisible: json['fileTreeVisible'] as bool? ?? true,
      gitVisible: json['gitVisible'] as bool? ?? true,
      searchVisible: json['searchVisible'] as bool? ?? true,
      boardVisible: json['boardVisible'] as bool? ?? true,
      rightToolsVisible: json['rightToolsVisible'] as bool? ?? true,
      sidebarVisible: json['sidebarVisible'] as bool? ?? true,
      rightToolsWidth: _doubleValue(
        json['rightToolsWidth'],
      ).clamp(minRightToolsWidth, double.infinity),
      sidebarWidth: _doubleValue(
        json['sidebarWidth'],
        fallback: defaultSidebarWidth,
      ).clamp(minSidebarWidth, double.infinity),
      homeSidebarWidth: _doubleValue(
        json['homeSidebarWidth'],
        fallback: defaultHomeSidebarWidth,
      ).clamp(minHomeSidebarWidth, double.infinity),
      workspaceNavWidth: _doubleValue(
        json['workspaceNavWidth'],
        fallback: defaultWorkspaceNavWidth,
      ).clamp(minWorkspaceNavWidth, maxWorkspaceNavWidth),
      themeMode: json['themeMode'] as String? ?? 'system',
      themeColorPreset: normalizeThemeColorPreset(
        json['themeColorPreset'] as String?,
      ),
      typographyScale: normalizeTypographyScale(
        json['typographyScale'] as String?,
      ),
      typographyScaleCustomMultiplier: clampTypographyCustomMultiplier(
        _doubleValue(
          json['typographyScaleCustomMultiplier'],
          fallback: kDefaultTypographyCustomMultiplier,
        ),
      ),
      uiZoomScale: normalizeTypographyScale(json['uiZoomScale'] as String?),
      uiZoomCustomMultiplier: clampTypographyCustomMultiplier(
        _doubleValue(
          json['uiZoomCustomMultiplier'],
          fallback: kDefaultTypographyCustomMultiplier,
        ),
      ),
      terminalThemeMode: _terminalThemeModeValue(
        json['terminalThemeMode'] as String?,
      ),
      locale: json['locale'] as String? ?? '',
      uiFontId: normalizeUiFontId(json['uiFontId'] as String?),
      monoFontId: normalizeMonoFontId(json['monoFontId'] as String?),
      workspaceTerminalVisible:
          json['workspaceTerminalVisible'] as bool? ?? false,
      workspaceTerminalHeight: _doubleValue(
        json['workspaceTerminalHeight'],
        fallback: defaultWorkspaceTerminalHeight,
      ).clamp(minWorkspaceTerminalHeight, double.infinity),
      markdownOpenMode:
          _enumValue(MarkdownOpenMode.values, json['markdownOpenMode']) ??
          MarkdownOpenMode.preview,
      cotExpandReasoningOnOpen:
          json['cotExpandReasoningOnOpen'] as bool? ?? false,
      cotExpandToolsOnOpen: json['cotExpandToolsOnOpen'] as bool? ?? false,
      chatUserMessageMode:
          _enumValue(ContentDisplayMode.values, json['chatUserMessageMode']) ??
          ContentDisplayMode.foldFixedHeight,
      chatCodeBlockMode:
          _enumValue(ContentDisplayMode.values, json['chatCodeBlockMode']) ??
          ContentDisplayMode.foldFixedHeight,
      fileCodeBlockMode:
          _enumValue(ContentDisplayMode.values, json['fileCodeBlockMode']) ??
          ContentDisplayMode.foldFixedHeight,
      floatingPanelLeft: _optionalDouble(json['floatingPanelLeft']),
      floatingPanelTop: _optionalDouble(json['floatingPanelTop']),
      floatingPanelWidth: _optionalDouble(json['floatingPanelWidth']),
      floatingPanelHeight: _optionalDouble(json['floatingPanelHeight']),
      floatingPanelRightInset: _optionalDouble(json['floatingPanelRightInset']),
      floatingPanelBottomInset: _optionalDouble(
        json['floatingPanelBottomInset'],
      ),
      floatingToggleDx: _optionalDouble(json['floatingToggleDx']),
      floatingToggleDy: _optionalDouble(json['floatingToggleDy']),
      floatingMaximized: json['floatingMaximized'] as bool? ?? false,
      filePreviewHost:
          _enumValue(FilePreviewHost.values, json['filePreviewHost']) ??
          FilePreviewHost.floating,
      foldToolCallCategories: _categorySet(json['foldToolCallCategories']),
    ).withAtLeastOneToolVisible();
  }

  static const defaultRightToolsWidth = 320.0;
  static const minRightToolsWidth = 240.0;
  static const defaultSidebarWidth = 260.0;
  static const minSidebarWidth = 180.0;
  static const defaultHomeSidebarWidth = 420.0;
  static const minHomeSidebarWidth = 280.0;
  static const defaultWorkspaceNavWidth = 220.0;
  static const minWorkspaceNavWidth = 200.0;
  static const maxWorkspaceNavWidth = 360.0;
  static const defaultWorkspaceTerminalHeight = 220.0;
  static const minWorkspaceTerminalHeight = 120.0;

  /// Categories folded into the thinking-process chain by default.
  static const Set<AiToolCallCategory> defaultFoldToolCallCategories = {
    AiToolCallCategory.read,
    AiToolCallCategory.write,
    AiToolCallCategory.edit,
    AiToolCallCategory.command,
    AiToolCallCategory.search,
    AiToolCallCategory.browser,
    AiToolCallCategory.mcp,
    AiToolCallCategory.task,
  };

  /// Minimum extent for the main workbench column beside a side panel.
  static const minWorkbenchMainWidth = 320.0;

  /// Minimum extent for the main workbench row above the bottom terminal.
  static const minWorkbenchMainHeight = 200.0;

  /// Minimum LLM provider detail column in the config split.
  static const minLlmProviderDetailWidth = 280.0;

  /// Minimum settings hub content column beside nav.
  static const minWorkspaceHubContentWidth = 480.0;

  final LayoutPreset preset;
  final WorkspaceEntryMode workspaceEntryMode;
  final String lastOpenedWorkspaceId;
  final bool appRailVisible;
  final bool membersVisible;
  final bool fileTreeVisible;
  final bool gitVisible;
  final bool searchVisible;
  final bool boardVisible;
  final bool rightToolsVisible;
  final bool sidebarVisible;
  final double rightToolsWidth;
  final double sidebarWidth;
  final double homeSidebarWidth;
  final double workspaceNavWidth;
  final String themeMode;
  final String themeColorPreset;
  final String typographyScale;
  final double typographyScaleCustomMultiplier;

  /// Whole-UI zoom level (relative preset, independent of text size). The
  /// effective [UiZoom] is the per-display baseline × this preset's multiplier;
  /// `standard` == the auto baseline.
  final String uiZoomScale;
  final double uiZoomCustomMultiplier;
  final String terminalThemeMode;
  final String locale;
  final String uiFontId;
  final String monoFontId;

  /// Legacy bottom-dock flag kept for JSON compat; layout always treats as false.
  final bool workspaceTerminalVisible;
  final double workspaceTerminalHeight;
  final MarkdownOpenMode markdownOpenMode;
  final bool cotExpandReasoningOnOpen;
  final bool cotExpandToolsOnOpen;
  final ContentDisplayMode chatUserMessageMode;
  final ContentDisplayMode chatCodeBlockMode;
  final ContentDisplayMode fileCodeBlockMode;
  final double? floatingPanelLeft;
  final double? floatingPanelTop;
  final double? floatingPanelWidth;
  final double? floatingPanelHeight;
  final double? floatingPanelRightInset;
  final double? floatingPanelBottomInset;
  final double? floatingToggleDx;
  final double? floatingToggleDy;
  final bool floatingMaximized;
  final FilePreviewHost filePreviewHost;

  final Set<AiToolCallCategory> foldToolCallCategories;

  LayoutPreferences copyWith({
    LayoutPreset? preset,
    WorkspaceEntryMode? workspaceEntryMode,
    String? lastOpenedWorkspaceId,
    bool? appRailVisible,
    bool? membersVisible,
    bool? fileTreeVisible,
    bool? gitVisible,
    bool? searchVisible,
    bool? boardVisible,
    bool? rightToolsVisible,
    bool? sidebarVisible,
    double? rightToolsWidth,
    double? sidebarWidth,
    double? homeSidebarWidth,
    double? workspaceNavWidth,
    String? themeMode,
    String? themeColorPreset,
    String? typographyScale,
    double? typographyScaleCustomMultiplier,
    String? uiZoomScale,
    double? uiZoomCustomMultiplier,
    String? terminalThemeMode,
    String? locale,
    String? uiFontId,
    String? monoFontId,
    bool? workspaceTerminalVisible,
    double? workspaceTerminalHeight,
    MarkdownOpenMode? markdownOpenMode,
    bool? cotExpandReasoningOnOpen,
    bool? cotExpandToolsOnOpen,
    ContentDisplayMode? chatUserMessageMode,
    ContentDisplayMode? chatCodeBlockMode,
    ContentDisplayMode? fileCodeBlockMode,
    double? floatingPanelLeft,
    double? floatingPanelTop,
    double? floatingPanelWidth,
    double? floatingPanelHeight,
    double? floatingPanelRightInset,
    double? floatingPanelBottomInset,
    double? floatingToggleDx,
    double? floatingToggleDy,
    bool? floatingMaximized,
    FilePreviewHost? filePreviewHost,
    Set<AiToolCallCategory>? foldToolCallCategories,
  }) {
    return LayoutPreferences(
      preset: preset ?? this.preset,
      workspaceEntryMode: workspaceEntryMode ?? this.workspaceEntryMode,
      lastOpenedWorkspaceId:
          lastOpenedWorkspaceId ?? this.lastOpenedWorkspaceId,
      appRailVisible: appRailVisible ?? this.appRailVisible,
      membersVisible: membersVisible ?? this.membersVisible,
      fileTreeVisible: fileTreeVisible ?? this.fileTreeVisible,
      gitVisible: gitVisible ?? this.gitVisible,
      searchVisible: searchVisible ?? this.searchVisible,
      boardVisible: boardVisible ?? this.boardVisible,
      rightToolsVisible: rightToolsVisible ?? this.rightToolsVisible,
      sidebarVisible: sidebarVisible ?? this.sidebarVisible,
      rightToolsWidth: (rightToolsWidth ?? this.rightToolsWidth).clamp(
        minRightToolsWidth,
        double.infinity,
      ),
      sidebarWidth: (sidebarWidth ?? this.sidebarWidth).clamp(
        minSidebarWidth,
        double.infinity,
      ),
      homeSidebarWidth: (homeSidebarWidth ?? this.homeSidebarWidth).clamp(
        minHomeSidebarWidth,
        double.infinity,
      ),
      workspaceNavWidth: (workspaceNavWidth ?? this.workspaceNavWidth).clamp(
        minWorkspaceNavWidth,
        maxWorkspaceNavWidth,
      ),
      themeMode: themeMode ?? this.themeMode,
      themeColorPreset: themeColorPreset ?? this.themeColorPreset,
      typographyScale: typographyScale == null
          ? this.typographyScale
          : normalizeTypographyScale(typographyScale),
      typographyScaleCustomMultiplier: typographyScaleCustomMultiplier == null
          ? this.typographyScaleCustomMultiplier
          : clampTypographyCustomMultiplier(typographyScaleCustomMultiplier),
      uiZoomScale: uiZoomScale == null
          ? this.uiZoomScale
          : normalizeTypographyScale(uiZoomScale),
      uiZoomCustomMultiplier: uiZoomCustomMultiplier == null
          ? this.uiZoomCustomMultiplier
          : clampTypographyCustomMultiplier(uiZoomCustomMultiplier),
      terminalThemeMode: terminalThemeMode == null
          ? this.terminalThemeMode
          : _terminalThemeModeValue(terminalThemeMode),
      locale: locale ?? this.locale,
      uiFontId: uiFontId == null ? this.uiFontId : normalizeUiFontId(uiFontId),
      monoFontId: monoFontId == null
          ? this.monoFontId
          : normalizeMonoFontId(monoFontId),
      workspaceTerminalVisible:
          workspaceTerminalVisible ?? this.workspaceTerminalVisible,
      workspaceTerminalHeight:
          (workspaceTerminalHeight ?? this.workspaceTerminalHeight).clamp(
            minWorkspaceTerminalHeight,
            double.infinity,
          ),
      markdownOpenMode: markdownOpenMode ?? this.markdownOpenMode,
      cotExpandReasoningOnOpen:
          cotExpandReasoningOnOpen ?? this.cotExpandReasoningOnOpen,
      cotExpandToolsOnOpen: cotExpandToolsOnOpen ?? this.cotExpandToolsOnOpen,
      chatUserMessageMode: chatUserMessageMode ?? this.chatUserMessageMode,
      chatCodeBlockMode: chatCodeBlockMode ?? this.chatCodeBlockMode,
      fileCodeBlockMode: fileCodeBlockMode ?? this.fileCodeBlockMode,
      floatingPanelLeft: floatingPanelLeft ?? this.floatingPanelLeft,
      floatingPanelTop: floatingPanelTop ?? this.floatingPanelTop,
      floatingPanelWidth: floatingPanelWidth ?? this.floatingPanelWidth,
      floatingPanelHeight: floatingPanelHeight ?? this.floatingPanelHeight,
      floatingPanelRightInset:
          floatingPanelRightInset ?? this.floatingPanelRightInset,
      floatingPanelBottomInset:
          floatingPanelBottomInset ?? this.floatingPanelBottomInset,
      floatingToggleDx: floatingToggleDx ?? this.floatingToggleDx,
      floatingToggleDy: floatingToggleDy ?? this.floatingToggleDy,
      floatingMaximized: floatingMaximized ?? this.floatingMaximized,
      filePreviewHost: filePreviewHost ?? this.filePreviewHost,
      foldToolCallCategories:
          foldToolCallCategories ?? this.foldToolCallCategories,
    ).withAtLeastOneToolVisible();
  }

  LayoutPreferences withAtLeastOneToolVisible() {
    if (membersVisible || fileTreeVisible) {
      return this;
    }
    return LayoutPreferences(
      preset: preset,
      workspaceEntryMode: workspaceEntryMode,
      lastOpenedWorkspaceId: lastOpenedWorkspaceId,
      appRailVisible: appRailVisible,
      membersVisible: true,
      fileTreeVisible: false,
      gitVisible: gitVisible,
      searchVisible: searchVisible,
      boardVisible: boardVisible,
      rightToolsVisible: rightToolsVisible,
      sidebarVisible: sidebarVisible,
      rightToolsWidth: rightToolsWidth,
      sidebarWidth: sidebarWidth,
      homeSidebarWidth: homeSidebarWidth,
      workspaceNavWidth: workspaceNavWidth,
      themeMode: themeMode,
      themeColorPreset: themeColorPreset,
      typographyScale: typographyScale,
      typographyScaleCustomMultiplier: typographyScaleCustomMultiplier,
      uiZoomScale: uiZoomScale,
      uiZoomCustomMultiplier: uiZoomCustomMultiplier,
      terminalThemeMode: terminalThemeMode,
      locale: locale,
      uiFontId: uiFontId,
      monoFontId: monoFontId,
      workspaceTerminalVisible: workspaceTerminalVisible,
      workspaceTerminalHeight: workspaceTerminalHeight,
      markdownOpenMode: markdownOpenMode,
      cotExpandReasoningOnOpen: cotExpandReasoningOnOpen,
      cotExpandToolsOnOpen: cotExpandToolsOnOpen,
      chatUserMessageMode: chatUserMessageMode,
      chatCodeBlockMode: chatCodeBlockMode,
      fileCodeBlockMode: fileCodeBlockMode,
      floatingPanelLeft: floatingPanelLeft,
      floatingPanelTop: floatingPanelTop,
      floatingPanelWidth: floatingPanelWidth,
      floatingPanelHeight: floatingPanelHeight,
      floatingPanelRightInset: floatingPanelRightInset,
      floatingPanelBottomInset: floatingPanelBottomInset,
      floatingToggleDx: floatingToggleDx,
      floatingToggleDy: floatingToggleDy,
      floatingMaximized: floatingMaximized,
      filePreviewHost: filePreviewHost,
      foldToolCallCategories: foldToolCallCategories,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'preset': preset.name,
      'workspaceEntryMode': workspaceEntryMode.name,
      'lastOpenedWorkspaceId': lastOpenedWorkspaceId,
      'appRailVisible': appRailVisible,
      'membersVisible': membersVisible,
      'fileTreeVisible': fileTreeVisible,
      'gitVisible': gitVisible,
      'searchVisible': searchVisible,
      'boardVisible': boardVisible,
      'rightToolsVisible': rightToolsVisible,
      'sidebarVisible': sidebarVisible,
      'rightToolsWidth': rightToolsWidth,
      'sidebarWidth': sidebarWidth,
      'homeSidebarWidth': homeSidebarWidth,
      'workspaceNavWidth': workspaceNavWidth,
      'themeMode': themeMode,
      'themeColorPreset': themeColorPreset,
      'typographyScale': typographyScale,
      'typographyScaleCustomMultiplier': typographyScaleCustomMultiplier,
      'uiZoomScale': uiZoomScale,
      'uiZoomCustomMultiplier': uiZoomCustomMultiplier,
      'terminalThemeMode': terminalThemeMode,
      'locale': locale,
      'uiFontId': uiFontId,
      'monoFontId': monoFontId,
      'workspaceTerminalVisible': workspaceTerminalVisible,
      'workspaceTerminalHeight': workspaceTerminalHeight,
      'markdownOpenMode': markdownOpenMode.name,
      'cotExpandReasoningOnOpen': cotExpandReasoningOnOpen,
      'cotExpandToolsOnOpen': cotExpandToolsOnOpen,
      'chatUserMessageMode': chatUserMessageMode.name,
      'chatCodeBlockMode': chatCodeBlockMode.name,
      'fileCodeBlockMode': fileCodeBlockMode.name,
      'floatingPanelLeft': floatingPanelLeft,
      'floatingPanelTop': floatingPanelTop,
      'floatingPanelWidth': floatingPanelWidth,
      'floatingPanelHeight': floatingPanelHeight,
      'floatingPanelRightInset': floatingPanelRightInset,
      'floatingPanelBottomInset': floatingPanelBottomInset,
      'floatingToggleDx': floatingToggleDx,
      'floatingToggleDy': floatingToggleDy,
      'floatingMaximized': floatingMaximized,
      'filePreviewHost': filePreviewHost.name,
      'foldToolCallCategories': foldToolCallCategories
          .map((c) => c.name)
          .toList(),
    };
  }
}

T? _enumValue<T extends Enum>(List<T> values, Object? raw) {
  if (raw is! String) {
    return null;
  }
  for (final value in values) {
    if (value.name == raw) {
      return value;
    }
  }
  return null;
}

double _doubleValue(Object? raw, {double fallback = 320.0}) {
  if (raw is num) {
    return raw.toDouble();
  }
  return fallback;
}

double? _optionalDouble(Object? raw) {
  if (raw is num) {
    return raw.toDouble();
  }
  return null;
}

String _terminalThemeModeValue(String? raw) {
  if (raw == 'adaptive' || raw == 'classicDark' || raw == 'highContrast') {
    return raw!;
  }
  return 'adaptive';
}

WorkspaceEntryMode _workspaceEntryModeFromJson(String? raw) {
  if (raw == 'lastWorkspace') {
    return WorkspaceEntryMode.lastWorkspace;
  }
  // Legacy `hub` and unknown values open home (no redirect shim).
  return WorkspaceEntryMode.home;
}

Set<AiToolCallCategory> _categorySet(Object? raw) {
  if (raw is! List) return LayoutPreferences.defaultFoldToolCallCategories;
  final out = <AiToolCallCategory>{};
  for (final value in raw) {
    if (value is! String) continue;
    for (final category in AiToolCallCategory.values) {
      if (category.name == value) {
        out.add(category);
        break;
      }
    }
  }
  return out;
}
