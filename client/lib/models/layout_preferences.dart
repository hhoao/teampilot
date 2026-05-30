import '../theme/app_theme.dart';
import '../theme/app_typography_scale.dart';

enum LayoutPreset { workbench, chatFocus, inspector }

enum ToolPanelPlacement { right, bottom }

enum ToolsArrangement { stacked, tabs }

class LayoutPreferences {
  const LayoutPreferences({
    this.preset = LayoutPreset.workbench,
    this.toolPlacement = ToolPanelPlacement.right,
    this.toolsArrangement = ToolsArrangement.stacked,
    this.appRailVisible = true,
    this.contextSidebarVisible = true,
    this.membersVisible = true,
    this.fileTreeVisible = true,
    this.rightToolsVisible = true,
    this.rightToolsWidth = defaultRightToolsWidth,
    this.bottomToolsHeight = defaultBottomToolsHeight,
    this.sidebarWidth = defaultSidebarWidth,
    this.workspaceNavWidth = defaultWorkspaceNavWidth,
    this.membersSplit = 0.42,
    this.themeMode = 'system',
    this.themeColorPreset = kDefaultThemeColorPreset,
    this.typographyScale = kDefaultTypographyScaleId,
    this.typographyScaleCustomMultiplier = kDefaultTypographyCustomMultiplier,
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
      toolPlacement:
          _enumValue(ToolPanelPlacement.values, json['toolPlacement']) ??
          ToolPanelPlacement.right,
      toolsArrangement:
          _enumValue(ToolsArrangement.values, json['toolsArrangement']) ??
          ToolsArrangement.stacked,
      appRailVisible: json['appRailVisible'] as bool? ?? true,
      contextSidebarVisible: json['contextSidebarVisible'] as bool? ?? true,
      membersVisible: json['membersVisible'] as bool? ?? true,
      fileTreeVisible: json['fileTreeVisible'] as bool? ?? true,
      rightToolsVisible: json['rightToolsVisible'] as bool? ?? true,
      rightToolsWidth: _doubleValue(
        json['rightToolsWidth'],
      ).clamp(minRightToolsWidth, maxRightToolsWidth),
      bottomToolsHeight: _doubleValue(
        json['bottomToolsHeight'],
      ).clamp(minBottomToolsHeight, maxBottomToolsHeight),
      sidebarWidth: _doubleValue(
        json['sidebarWidth'],
        fallback: defaultSidebarWidth,
      ).clamp(minSidebarWidth, maxSidebarWidth),
      workspaceNavWidth: _doubleValue(
        json['workspaceNavWidth'],
        fallback: defaultWorkspaceNavWidth,
      ).clamp(minWorkspaceNavWidth, maxWorkspaceNavWidth),
      membersSplit: _doubleValue(
        json['membersSplit'],
        fallback: 0.42,
      ).clamp(0.25, 0.75),
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
  static const defaultBottomToolsHeight = 240.0;
  static const defaultSidebarWidth = 260.0;
  static const minSidebarWidth = 180.0;
  static const maxSidebarWidth = 420.0;
  static const defaultWorkspaceNavWidth = 220.0;
  static const minWorkspaceNavWidth = 200.0;
  static const maxWorkspaceNavWidth = 360.0;
  static const minBottomToolsHeight = 180.0;
  static const maxBottomToolsHeight = 420.0;
  static const defaultWorkspaceTerminalHeight = 220.0;
  static const minWorkspaceTerminalHeight = 120.0;
  static const maxWorkspaceTerminalHeight = 480.0;
  static const defaultWorkspaceTerminalSessionSidebarWidth = 200.0;
  static const minWorkspaceTerminalSessionSidebarWidth = 140.0;
  static const maxWorkspaceTerminalSessionSidebarWidth = 420.0;

  final LayoutPreset preset;
  final ToolPanelPlacement toolPlacement;
  final ToolsArrangement toolsArrangement;
  final bool appRailVisible;
  final bool contextSidebarVisible;
  final bool membersVisible;
  final bool fileTreeVisible;
  final bool rightToolsVisible;
  final double rightToolsWidth;
  final double bottomToolsHeight;
  final double sidebarWidth;
  final double workspaceNavWidth;
  final double membersSplit;
  final String themeMode;
  final String themeColorPreset;
  final String typographyScale;
  final double typographyScaleCustomMultiplier;
  final String terminalThemeMode;
  final String locale;
  final bool workspaceTerminalVisible;
  final double workspaceTerminalHeight;
  final double workspaceTerminalSessionSidebarWidth;

  LayoutPreferences copyWith({
    LayoutPreset? preset,
    ToolPanelPlacement? toolPlacement,
    ToolsArrangement? toolsArrangement,
    bool? appRailVisible,
    bool? contextSidebarVisible,
    bool? membersVisible,
    bool? fileTreeVisible,
    bool? rightToolsVisible,
    double? rightToolsWidth,
    double? bottomToolsHeight,
    double? sidebarWidth,
    double? workspaceNavWidth,
    double? membersSplit,
    String? themeMode,
    String? themeColorPreset,
    String? typographyScale,
    double? typographyScaleCustomMultiplier,
    String? terminalThemeMode,
    String? locale,
    bool? workspaceTerminalVisible,
    double? workspaceTerminalHeight,
    double? workspaceTerminalSessionSidebarWidth,
  }) {
    return LayoutPreferences(
      preset: preset ?? this.preset,
      toolPlacement: toolPlacement ?? this.toolPlacement,
      toolsArrangement: toolsArrangement ?? this.toolsArrangement,
      appRailVisible: appRailVisible ?? this.appRailVisible,
      contextSidebarVisible:
          contextSidebarVisible ?? this.contextSidebarVisible,
      membersVisible: membersVisible ?? this.membersVisible,
      fileTreeVisible: fileTreeVisible ?? this.fileTreeVisible,
      rightToolsVisible: rightToolsVisible ?? this.rightToolsVisible,
      rightToolsWidth: (rightToolsWidth ?? this.rightToolsWidth).clamp(
        minRightToolsWidth,
        maxRightToolsWidth,
      ),
      bottomToolsHeight: (bottomToolsHeight ?? this.bottomToolsHeight).clamp(
        minBottomToolsHeight,
        maxBottomToolsHeight,
      ),
      sidebarWidth: (sidebarWidth ?? this.sidebarWidth).clamp(
        minSidebarWidth,
        maxSidebarWidth,
      ),
      workspaceNavWidth: (workspaceNavWidth ?? this.workspaceNavWidth).clamp(
        minWorkspaceNavWidth,
        maxWorkspaceNavWidth,
      ),
      membersSplit: (membersSplit ?? this.membersSplit).clamp(0.25, 0.75),
      themeMode: themeMode ?? this.themeMode,
      themeColorPreset: themeColorPreset ?? this.themeColorPreset,
      typographyScale: typographyScale == null
          ? this.typographyScale
          : normalizeTypographyScale(typographyScale),
      typographyScaleCustomMultiplier: typographyScaleCustomMultiplier == null
          ? this.typographyScaleCustomMultiplier
          : clampTypographyCustomMultiplier(typographyScaleCustomMultiplier),
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
      toolPlacement: toolPlacement,
      toolsArrangement: toolsArrangement,
      appRailVisible: appRailVisible,
      contextSidebarVisible: contextSidebarVisible,
      membersVisible: true,
      fileTreeVisible: false,
      rightToolsVisible: rightToolsVisible,
      rightToolsWidth: rightToolsWidth,
      bottomToolsHeight: bottomToolsHeight,
      sidebarWidth: sidebarWidth,
      workspaceNavWidth: workspaceNavWidth,
      membersSplit: membersSplit,
      themeMode: themeMode,
      themeColorPreset: themeColorPreset,
      typographyScale: typographyScale,
      typographyScaleCustomMultiplier: typographyScaleCustomMultiplier,
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
      'toolPlacement': toolPlacement.name,
      'toolsArrangement': toolsArrangement.name,
      'appRailVisible': appRailVisible,
      'contextSidebarVisible': contextSidebarVisible,
      'membersVisible': membersVisible,
      'fileTreeVisible': fileTreeVisible,
      'rightToolsVisible': rightToolsVisible,
      'rightToolsWidth': rightToolsWidth,
      'bottomToolsHeight': bottomToolsHeight,
      'sidebarWidth': sidebarWidth,
      'workspaceNavWidth': workspaceNavWidth,
      'membersSplit': membersSplit,
      'themeMode': themeMode,
      'themeColorPreset': themeColorPreset,
      'typographyScale': typographyScale,
      'typographyScaleCustomMultiplier': typographyScaleCustomMultiplier,
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
