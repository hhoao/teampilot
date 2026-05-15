import '../theme/app_theme.dart';

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
    this.rightToolsWidth = defaultRightToolsWidth,
    this.bottomToolsHeight = defaultBottomToolsHeight,
    this.sidebarWidth = defaultSidebarWidth,
    this.membersSplit = 0.42,
    this.themeMode = 'system',
    this.themeColorPreset = 'graphite',
    this.locale = '',
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
      membersSplit: _doubleValue(
        json['membersSplit'],
        fallback: 0.42,
      ).clamp(0.25, 0.75),
      themeMode: json['themeMode'] as String? ?? 'system',
      themeColorPreset: normalizeThemeColorPreset(
        json['themeColorPreset'] as String?,
      ),
      locale: json['locale'] as String? ?? '',
    ).withAtLeastOneToolVisible();
  }

  static const defaultRightToolsWidth = 320.0;
  static const minRightToolsWidth = 240.0;
  static const maxRightToolsWidth = 520.0;
  static const defaultBottomToolsHeight = 240.0;
  static const defaultSidebarWidth = 260.0;
  static const minSidebarWidth = 180.0;
  static const maxSidebarWidth = 420.0;
  static const minBottomToolsHeight = 180.0;
  static const maxBottomToolsHeight = 420.0;

  final LayoutPreset preset;
  final ToolPanelPlacement toolPlacement;
  final ToolsArrangement toolsArrangement;
  final bool appRailVisible;
  final bool contextSidebarVisible;
  final bool membersVisible;
  final bool fileTreeVisible;
  final double rightToolsWidth;
  final double bottomToolsHeight;
  final double sidebarWidth;
  final double membersSplit;
  final String themeMode;
  final String themeColorPreset;
  final String locale;

  LayoutPreferences copyWith({
    LayoutPreset? preset,
    ToolPanelPlacement? toolPlacement,
    ToolsArrangement? toolsArrangement,
    bool? appRailVisible,
    bool? contextSidebarVisible,
    bool? membersVisible,
    bool? fileTreeVisible,
    double? rightToolsWidth,
    double? bottomToolsHeight,
    double? sidebarWidth,
    double? membersSplit,
    String? themeMode,
    String? themeColorPreset,
    String? locale,
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
      membersSplit: (membersSplit ?? this.membersSplit).clamp(0.25, 0.75),
      themeMode: themeMode ?? this.themeMode,
      themeColorPreset: themeColorPreset ?? this.themeColorPreset,
      locale: locale ?? this.locale,
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
      rightToolsWidth: rightToolsWidth,
      bottomToolsHeight: bottomToolsHeight,
      sidebarWidth: sidebarWidth,
      membersSplit: membersSplit,
      themeMode: themeMode,
      themeColorPreset: themeColorPreset,
      locale: locale,
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
      'rightToolsWidth': rightToolsWidth,
      'bottomToolsHeight': bottomToolsHeight,
      'sidebarWidth': sidebarWidth,
      'membersSplit': membersSplit,
      'themeMode': themeMode,
      'themeColorPreset': themeColorPreset,
      'locale': locale,
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
