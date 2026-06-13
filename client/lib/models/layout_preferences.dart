import '../theme/app_theme.dart';
import '../theme/app_typography_scale.dart';

enum LayoutPreset { workbench, chatFocus, inspector }

enum WorkspaceEntryMode { home, lastProject }

class LayoutPreferences {
  const LayoutPreferences({
    this.preset = LayoutPreset.workbench,
    this.workspaceEntryMode = WorkspaceEntryMode.home,
    this.lastOpenedProjectId = '',
    this.appRailVisible = true,
    this.membersVisible = true,
    this.fileTreeVisible = true,
    this.gitVisible = true,
    this.rightToolsVisible = true,
    this.rightToolsWidth = defaultRightToolsWidth,
    this.sidebarWidth = defaultSidebarWidth,
    this.workspaceNavWidth = defaultWorkspaceNavWidth,
    this.themeMode = 'system',
    this.themeColorPreset = kDefaultThemeColorPreset,
    this.typographyScale = kDefaultTypographyScaleId,
    this.typographyScaleCustomMultiplier = kDefaultTypographyCustomMultiplier,
    this.uiZoomScale = kDefaultTypographyScaleId,
    this.uiZoomCustomMultiplier = kDefaultTypographyCustomMultiplier,
    this.terminalThemeMode = 'adaptive',
    this.locale = '',
    this.workspaceTerminalVisible = false,
    this.workspaceTerminalHeight = defaultWorkspaceTerminalHeight,
    this.workspaceTerminalSessionSidebarWidth =
        defaultWorkspaceTerminalSessionSidebarWidth,
  });

  factory LayoutPreferences.fromJson(Map<String, Object?> json) {
    return LayoutPreferences(
      preset:
          _enumValue(LayoutPreset.values, json['preset']) ??
          LayoutPreset.workbench,
      workspaceEntryMode: _workspaceEntryModeFromJson(
        json['workspaceEntryMode'] as String?,
      ),
      lastOpenedProjectId: json['lastOpenedProjectId'] as String? ?? '',
      appRailVisible: json['appRailVisible'] as bool? ?? true,
      membersVisible: json['membersVisible'] as bool? ?? true,
      fileTreeVisible: json['fileTreeVisible'] as bool? ?? true,
      gitVisible: json['gitVisible'] as bool? ?? true,
      rightToolsVisible: json['rightToolsVisible'] as bool? ?? true,
      rightToolsWidth: _doubleValue(
        json['rightToolsWidth'],
      ).clamp(minRightToolsWidth, maxRightToolsWidth),
      sidebarWidth: _doubleValue(
        json['sidebarWidth'],
        fallback: defaultSidebarWidth,
      ).clamp(minSidebarWidth, maxSidebarWidth),
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
      workspaceTerminalVisible:
          json['workspaceTerminalVisible'] as bool? ?? false,
      workspaceTerminalHeight: _doubleValue(
        json['workspaceTerminalHeight'],
        fallback: defaultWorkspaceTerminalHeight,
      ).clamp(minWorkspaceTerminalHeight, maxWorkspaceTerminalHeight),
      workspaceTerminalSessionSidebarWidth: _doubleValue(
        json['workspaceTerminalSessionSidebarWidth'],
        fallback: defaultWorkspaceTerminalSessionSidebarWidth,
      ).clamp(
        minWorkspaceTerminalSessionSidebarWidth,
        maxWorkspaceTerminalSessionSidebarWidth,
      ),
    ).withAtLeastOneToolVisible();
  }

  static const defaultRightToolsWidth = 320.0;
  static const minRightToolsWidth = 240.0;
  static const maxRightToolsWidth = 520.0;
  static const defaultSidebarWidth = 260.0;
  static const minSidebarWidth = 180.0;
  static const maxSidebarWidth = 420.0;
  static const defaultWorkspaceNavWidth = 220.0;
  static const minWorkspaceNavWidth = 200.0;
  static const maxWorkspaceNavWidth = 360.0;
  static const defaultWorkspaceTerminalHeight = 220.0;
  static const minWorkspaceTerminalHeight = 120.0;
  static const maxWorkspaceTerminalHeight = 480.0;
  static const defaultWorkspaceTerminalSessionSidebarWidth = 200.0;
  static const minWorkspaceTerminalSessionSidebarWidth = 140.0;
  static const maxWorkspaceTerminalSessionSidebarWidth = 420.0;

  /// Minimum extent for the main workbench column beside a side panel.
  static const minWorkbenchMainWidth = 320.0;

  /// Minimum terminal grid width when a session sidebar is shown.
  static const minWorkspaceTerminalMainWidth = 200.0;

  /// Minimum LLM provider detail column in the config split.
  static const minLlmProviderDetailWidth = 280.0;

  /// Minimum settings hub content column beside nav.
  static const minWorkspaceHubContentWidth = 480.0;

  final LayoutPreset preset;
  final WorkspaceEntryMode workspaceEntryMode;
  final String lastOpenedProjectId;
  final bool appRailVisible;
  final bool membersVisible;
  final bool fileTreeVisible;
  final bool gitVisible;
  final bool rightToolsVisible;
  final double rightToolsWidth;
  final double sidebarWidth;
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
  final bool workspaceTerminalVisible;
  final double workspaceTerminalHeight;
  final double workspaceTerminalSessionSidebarWidth;

  LayoutPreferences copyWith({
    LayoutPreset? preset,
    WorkspaceEntryMode? workspaceEntryMode,
    String? lastOpenedProjectId,
    bool? appRailVisible,
    bool? membersVisible,
    bool? fileTreeVisible,
    bool? gitVisible,
    bool? rightToolsVisible,
    double? rightToolsWidth,
    double? sidebarWidth,
    double? workspaceNavWidth,
    String? themeMode,
    String? themeColorPreset,
    String? typographyScale,
    double? typographyScaleCustomMultiplier,
    String? uiZoomScale,
    double? uiZoomCustomMultiplier,
    String? terminalThemeMode,
    String? locale,
    bool? workspaceTerminalVisible,
    double? workspaceTerminalHeight,
    double? workspaceTerminalSessionSidebarWidth,
  }) {
    return LayoutPreferences(
      preset: preset ?? this.preset,
      workspaceEntryMode: workspaceEntryMode ?? this.workspaceEntryMode,
      lastOpenedProjectId: lastOpenedProjectId ?? this.lastOpenedProjectId,
      appRailVisible: appRailVisible ?? this.appRailVisible,
      membersVisible: membersVisible ?? this.membersVisible,
      fileTreeVisible: fileTreeVisible ?? this.fileTreeVisible,
      gitVisible: gitVisible ?? this.gitVisible,
      rightToolsVisible: rightToolsVisible ?? this.rightToolsVisible,
      rightToolsWidth: (rightToolsWidth ?? this.rightToolsWidth).clamp(
        minRightToolsWidth,
        maxRightToolsWidth,
      ),
      sidebarWidth: (sidebarWidth ?? this.sidebarWidth).clamp(
        minSidebarWidth,
        maxSidebarWidth,
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
      workspaceTerminalVisible:
          workspaceTerminalVisible ?? this.workspaceTerminalVisible,
      workspaceTerminalHeight: (workspaceTerminalHeight ??
              this.workspaceTerminalHeight)
          .clamp(minWorkspaceTerminalHeight, maxWorkspaceTerminalHeight),
      workspaceTerminalSessionSidebarWidth:
          (workspaceTerminalSessionSidebarWidth ??
                  this.workspaceTerminalSessionSidebarWidth)
              .clamp(
                minWorkspaceTerminalSessionSidebarWidth,
                maxWorkspaceTerminalSessionSidebarWidth,
              ),
    ).withAtLeastOneToolVisible();
  }

  LayoutPreferences withAtLeastOneToolVisible() {
    if (membersVisible || fileTreeVisible) {
      return this;
    }
    return LayoutPreferences(
      preset: preset,
      workspaceEntryMode: workspaceEntryMode,
      lastOpenedProjectId: lastOpenedProjectId,
      appRailVisible: appRailVisible,
      membersVisible: true,
      fileTreeVisible: false,
      gitVisible: gitVisible,
      rightToolsVisible: rightToolsVisible,
      rightToolsWidth: rightToolsWidth,
      sidebarWidth: sidebarWidth,
      workspaceNavWidth: workspaceNavWidth,
      themeMode: themeMode,
      themeColorPreset: themeColorPreset,
      typographyScale: typographyScale,
      typographyScaleCustomMultiplier: typographyScaleCustomMultiplier,
      uiZoomScale: uiZoomScale,
      uiZoomCustomMultiplier: uiZoomCustomMultiplier,
      terminalThemeMode: terminalThemeMode,
      locale: locale,
      workspaceTerminalVisible: workspaceTerminalVisible,
      workspaceTerminalHeight: workspaceTerminalHeight,
      workspaceTerminalSessionSidebarWidth:
          workspaceTerminalSessionSidebarWidth,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'preset': preset.name,
      'workspaceEntryMode': workspaceEntryMode.name,
      'lastOpenedProjectId': lastOpenedProjectId,
      'appRailVisible': appRailVisible,
      'membersVisible': membersVisible,
      'fileTreeVisible': fileTreeVisible,
      'gitVisible': gitVisible,
      'rightToolsVisible': rightToolsVisible,
      'rightToolsWidth': rightToolsWidth,
      'sidebarWidth': sidebarWidth,
      'workspaceNavWidth': workspaceNavWidth,
      'themeMode': themeMode,
      'themeColorPreset': themeColorPreset,
      'typographyScale': typographyScale,
      'typographyScaleCustomMultiplier': typographyScaleCustomMultiplier,
      'uiZoomScale': uiZoomScale,
      'uiZoomCustomMultiplier': uiZoomCustomMultiplier,
      'terminalThemeMode': terminalThemeMode,
      'locale': locale,
      'workspaceTerminalVisible': workspaceTerminalVisible,
      'workspaceTerminalHeight': workspaceTerminalHeight,
      'workspaceTerminalSessionSidebarWidth':
          workspaceTerminalSessionSidebarWidth,
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

String _terminalThemeModeValue(String? raw) {
  if (raw == 'adaptive' || raw == 'classicDark' || raw == 'highContrast') {
    return raw!;
  }
  return 'adaptive';
}

WorkspaceEntryMode _workspaceEntryModeFromJson(String? raw) {
  if (raw == 'lastProject') {
    return WorkspaceEntryMode.lastProject;
  }
  // Legacy `hub` and unknown values open home (no redirect shim).
  return WorkspaceEntryMode.home;
}
