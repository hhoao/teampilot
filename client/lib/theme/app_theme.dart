import 'package:flutter/material.dart';

import 'app_workspace_settings_theme.dart';

class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.background,
    required this.surface,
    required this.surfaceVariant,
    required this.cardBackground,
    required this.topbarBackground,
    required this.sidebarBackground,
    required this.railBackground,
    required this.workspaceBackground,
    required this.rightPanelBackground,
    required this.inputFill,
    required this.inputBorder,
    required this.inputBorderFocused,
    required this.border,
    required this.subtleBorder,
    required this.selectedBackground,
    required this.selectedBorder,
    required this.unselectedBackground,
    required this.unselectedBorder,
    required this.linkText,
    required this.accentBlue,
    required this.accentBlueLight,
    required this.accentGreen,
    required this.accentGreenLight,
    required this.warningBackground,
    required this.warningBorder,
    required this.warningText,
    required this.successBackground,
    required this.successBorder,
    required this.successText,
    required this.userBubbleBackground,
    required this.systemBubbleBackground,
    required this.assistantBubbleBackground,
    required this.codeBackground,
    required this.teamSelectorBackground,
    required this.teamSelectorBorder,
    required this.railButtonSelectedBg,
    required this.railButtonUnselectedBg,
    required this.railButtonSelectedFg,
    required this.railButtonUnselectedFg,
    required this.selectedMemberBg,
    required this.unselectedMemberBg,
    required this.typeBadgeApiBg,
    required this.typeBadgeApiBorder,
    required this.typeBadgeApiText,
    required this.typeBadgeAccountBg,
    required this.typeBadgeAccountBorder,
    required this.typeBadgeAccountText,
    required this.logoGradientStart,
    required this.logoGradientEnd,
    required this.readOnlyFieldBg,
    required this.readOnlyFieldBorder,
    required this.readOnlyFieldText,
    required this.tabBarDivider,
    required this.statBoxBg,
    required this.statBoxBorder,
    required this.statBoxWarnBorder,
    required this.emptyMessageText,
  });

  final Color background;
  final Color surface;
  final Color surfaceVariant;
  final Color cardBackground;
  final Color topbarBackground;
  final Color sidebarBackground;
  final Color railBackground;
  final Color workspaceBackground;
  final Color rightPanelBackground;
  final Color inputFill;
  final Color inputBorder;
  final Color inputBorderFocused;
  final Color border;
  final Color subtleBorder;
  final Color selectedBackground;
  final Color selectedBorder;
  final Color unselectedBackground;
  final Color unselectedBorder;
  final Color linkText;
  final Color accentBlue;
  final Color accentBlueLight;
  final Color accentGreen;
  final Color accentGreenLight;
  final Color warningBackground;
  final Color warningBorder;
  final Color warningText;
  final Color successBackground;
  final Color successBorder;
  final Color successText;
  final Color userBubbleBackground;
  final Color systemBubbleBackground;
  final Color assistantBubbleBackground;
  final Color codeBackground;
  final Color teamSelectorBackground;
  final Color teamSelectorBorder;
  final Color railButtonSelectedBg;
  final Color railButtonUnselectedBg;
  final Color railButtonSelectedFg;
  final Color railButtonUnselectedFg;
  final Color selectedMemberBg;
  final Color unselectedMemberBg;
  final Color typeBadgeApiBg;
  final Color typeBadgeApiBorder;
  final Color typeBadgeApiText;
  final Color typeBadgeAccountBg;
  final Color typeBadgeAccountBorder;
  final Color typeBadgeAccountText;
  final Color logoGradientStart;
  final Color logoGradientEnd;
  final Color readOnlyFieldBg;
  final Color readOnlyFieldBorder;
  final Color readOnlyFieldText;
  final Color tabBarDivider;
  final Color statBoxBg;
  final Color statBoxBorder;
  final Color statBoxWarnBorder;
  final Color emptyMessageText;

  static const _dark = AppColors(
    background: Color(0xFF080807),
    surface: Color(0xFF0B0908),
    surfaceVariant: Color(0xFF100E0C),
    cardBackground: Color(0xFF0B0908),
    topbarBackground: Color(0xFF0B0908),
    sidebarBackground: Color(0xFF0B0908),
    railBackground: Color(0xFF080807),
    workspaceBackground: Color(0xFF080807),
    rightPanelBackground: Color(0xFF0D0C0B),
    inputFill: Color(0xFF0E0A08),
    inputBorder: Color(0xFF2A2623),
    inputBorderFocused: Color(0xFF5B8DEF),
    border: Color(0xFF272321),
    subtleBorder: Color(0xFF1B1816),
    selectedBackground: Color(0xFF2B2727),
    selectedBorder: Color(0xFF3A3431),
    unselectedBackground: Color(0xFF100E0C),
    unselectedBorder: Color(0xFF272321),
    linkText: Color(0xFF93C5FD),
    accentBlue: Color(0xFF60A5FA),
    accentBlueLight: Color(0xFFDBEAFE),
    accentGreen: Color(0xFF34D399),
    accentGreenLight: Color(0xFFA7F3D0),
    warningBackground: Color(0x1FFFCC80),
    warningBorder: Color(0x66FFCC80),
    warningText: Color(0xFFFFCC80),
    successBackground: Color(0x1434D399),
    successBorder: Color(0x3834D399),
    successText: Color(0xFFA7F3D0),
    userBubbleBackground: Color(0xFF1D4ED8),
    systemBubbleBackground: Color(0x1F94A3B8),
    assistantBubbleBackground: Color(0xFF100E0C),
    codeBackground: Color(0xFF05070B),
    // Match sidebar: avoid tinted “input” blue on black chrome.
    teamSelectorBackground: Color(0xFF0B0908),
    teamSelectorBorder: Color(0xFF272321),
    railButtonSelectedBg: Color(0x3D60A5FA),
    railButtonUnselectedBg: Color(0x1F94A3B8),
    railButtonSelectedFg: Color(0xFFDBEAFE),
    railButtonUnselectedFg: Color(0xFFBFBFBF),
    selectedMemberBg: Color(0x2E064E3B),
    unselectedMemberBg: Color(0xFF100E0C),
    typeBadgeApiBg: Color(0x1C60A5FA),
    typeBadgeApiBorder: Color(0x3860A5FA),
    typeBadgeApiText: Color(0xFF93C5FD),
    typeBadgeAccountBg: Color(0x1C34D399),
    typeBadgeAccountBorder: Color(0x3834D399),
    typeBadgeAccountText: Color(0xFFA7F3D0),
    logoGradientStart: Color(0xFF60A5FA),
    logoGradientEnd: Color(0xFF34D399),
    readOnlyFieldBg: Color(0xFF0E0A08),
    readOnlyFieldBorder: Color(0xFF2A2623),
    readOnlyFieldText: Color(0xFFDBEAFE),
    tabBarDivider: Color(0xFF1B1816),
    statBoxBg: Color(0xFF100E0C),
    statBoxBorder: Color(0xFF272321),
    statBoxWarnBorder: Color(0x40FBBF24),
    emptyMessageText: Color(0xFF8B949E),
  );

  static const _light = AppColors(
    background: Color(0xFFF5F6F8),
    surface: Color(0xFFFFFFFF),
    surfaceVariant: Color(0xFFF3F4F6),
    cardBackground: Color(0xFFFFFFFF),
    topbarBackground: Color(0xFFFFFFFF),
    sidebarBackground: Color(0xFFF0F1F3),
    railBackground: Color(0xFFE8EAED),
    workspaceBackground: Color(0xFFF5F6F8),
    rightPanelBackground: Color(0xFFF8F9FA),
    inputFill: Color(0xFFF3F4F6),
    inputBorder: Color(0xFFD1D5DB),
    inputBorderFocused: Color(0xFF3B6FD4),
    border: Color(0xFFE5E7EB),
    subtleBorder: Color(0xFFE5E7EB),
    selectedBackground: Color(0xFFE8EDFB),
    selectedBorder: Color(0xFF93B5F5),
    unselectedBackground: Color(0xFFF3F4F6),
    unselectedBorder: Color(0xFFD1D5DB),
    linkText: Color(0xFF3B6FD4),
    accentBlue: Color(0xFF3B6FD4),
    accentBlueLight: Color(0xFF1E40AF),
    accentGreen: Color(0xFF2AAF86),
    accentGreenLight: Color(0xFF064E3B),
    warningBackground: Color(0xFFFFF8E1),
    warningBorder: Color(0xFFFBBF24),
    warningText: Color(0xFF92400E),
    successBackground: Color(0xFFECFDF5),
    successBorder: Color(0xFF6EE7B7),
    successText: Color(0xFF064E3B),
    userBubbleBackground: Color(0xFF3B6FD4),
    systemBubbleBackground: Color(0xFFF3F4F6),
    assistantBubbleBackground: Color(0xFFF9FAFB),
    codeBackground: Color(0xFFF3F4F6),
    teamSelectorBackground: Color(0xFFF0F1F3),
    teamSelectorBorder: Color(0xFFE5E7EB),
    railButtonSelectedBg: Color(0xFFDBEAFE),
    railButtonUnselectedBg: Color(0xFFE5E7EB),
    railButtonSelectedFg: Color(0xFF1E40AF),
    railButtonUnselectedFg: Color(0xFF6B7280),
    selectedMemberBg: Color(0xFFD1FAE5),
    unselectedMemberBg: Color(0xFFF3F4F6),
    typeBadgeApiBg: Color(0xFFDBEAFE),
    typeBadgeApiBorder: Color(0xFF93C5FD),
    typeBadgeApiText: Color(0xFF1E40AF),
    typeBadgeAccountBg: Color(0xFFD1FAE5),
    typeBadgeAccountBorder: Color(0xFF6EE7B7),
    typeBadgeAccountText: Color(0xFF064E3B),
    logoGradientStart: Color(0xFF3B6FD4),
    logoGradientEnd: Color(0xFF2AAF86),
    readOnlyFieldBg: Color(0xFFF3F4F6),
    readOnlyFieldBorder: Color(0xFFD1D5DB),
    readOnlyFieldText: Color(0xFF1F2937),
    tabBarDivider: Color(0xFFE5E7EB),
    statBoxBg: Color(0xFFF9FAFB),
    statBoxBorder: Color(0xFFE5E7EB),
    statBoxWarnBorder: Color(0xFFFBBF24),
    emptyMessageText: Color(0xFF9CA3AF),
  );

  static AppColors of(BuildContext context) =>
      Theme.of(context).extension<AppColors>()!;

  @override
  AppColors copyWith() => this;

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) => this;
}

ThemeData buildDarkTheme() {
  const colors = AppColors._dark;
  return _buildTheme(Brightness.dark, colors);
}

ThemeData buildLightTheme() {
  const colors = AppColors._light;
  return _buildTheme(Brightness.light, colors);
}

ThemeData _buildTheme(Brightness brightness, AppColors colors) {
  final isDark = brightness == Brightness.dark;
  final textBase = isDark ? Colors.white : const Color(0xFF111827);
  final pillShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(999),
  );
  final buttonPadding = WidgetStateProperty.all(
    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
  );
  return ThemeData(
    brightness: brightness,
    fontFamily: 'sans-serif',
    fontFamilyFallback: const ['sans-serif'],
    colorScheme: ColorScheme(
      brightness: brightness,
      primary: const Color(0xFF5B8DEF),
      onPrimary: Colors.white,
      secondary: const Color(0xFF38CFA2),
      onSecondary: isDark ? Colors.black : Colors.white,
      error: const Color(0xFFFF7A7A),
      onError: isDark ? Colors.black : Colors.white,
      surface: colors.surface,
      onSurface: isDark ? Colors.white : const Color(0xFF111827),
    ),
    scaffoldBackgroundColor: isDark
        ? const Color(0xFF090807)
        : const Color(0xFFF8F9FA),
    dividerColor: colors.subtleBorder,
    filledButtonTheme: FilledButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.all(colors.accentBlue),
        foregroundColor: WidgetStateProperty.all(Colors.white),
        iconColor: WidgetStateProperty.all(Colors.white),
        overlayColor: WidgetStateProperty.all(
          Colors.white.withValues(alpha: 0.10),
        ),
        shape: WidgetStateProperty.all(pillShape),
        padding: buttonPadding,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: ButtonStyle(
        foregroundColor: WidgetStateProperty.all(colors.linkText),
        iconColor: WidgetStateProperty.all(colors.linkText),
        overlayColor: WidgetStateProperty.all(
          colors.linkText.withValues(alpha: 0.08),
        ),
        side: WidgetStateProperty.all(BorderSide(color: colors.inputBorder)),
        shape: WidgetStateProperty.all(pillShape),
        padding: buttonPadding,
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: ButtonStyle(
        foregroundColor: WidgetStateProperty.all(
          textBase.withValues(alpha: 0.86),
        ),
        overlayColor: WidgetStateProperty.all(textBase.withValues(alpha: 0.08)),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return Colors.white;
        return textBase.withValues(alpha: 0.78);
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return colors.accentBlue;
        }
        return textBase.withValues(alpha: 0.14);
      }),
      trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return textBase;
          return textBase.withValues(alpha: 0.66);
        }),
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return colors.selectedBackground;
          }
          return colors.cardBackground;
        }),
        side: WidgetStateProperty.all(BorderSide(color: colors.border)),
        shape: WidgetStateProperty.all(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
    ),
    // Aligns PopupMenuButton / showMenu with custom dropdown overlay (card,
    // border, shadow; no M3 surface tint halo).
    popupMenuTheme: PopupMenuThemeData(
      color: colors.cardBackground,
      surfaceTintColor: Colors.transparent,
      elevation: 14,
      shadowColor: Colors.black.withValues(alpha: isDark ? 0.45 : 0.12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: colors.subtleBorder),
      ),
      textStyle: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        height: 1.25,
        color: textBase,
      ),
      iconColor: textBase.withValues(alpha: 0.72),
      menuPadding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
    ),
    menuTheme: MenuThemeData(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(colors.cardBackground),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        elevation: const WidgetStatePropertyAll(14),
        shadowColor: WidgetStatePropertyAll(
          Colors.black.withValues(alpha: isDark ? 0.45 : 0.12),
        ),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(color: colors.subtleBorder),
          ),
        ),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(vertical: 4, horizontal: 4),
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: colors.inputFill,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: colors.inputBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: colors.inputBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: colors.inputBorderFocused),
      ),
    ),
    useMaterial3: true,
    extensions: [colors, const AppWorkspaceSettingsTokens()],
  );
}
