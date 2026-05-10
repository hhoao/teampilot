import 'package:flutter/material.dart';

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
    background: Color(0xFF090D13),
    surface: Color(0xFF0F172A),
    surfaceVariant: Color(0xFF111827),
    cardBackground: Color(0xFF0F172A),
    topbarBackground: Color(0xFF0B1017),
    sidebarBackground: Color(0xFF111827),
    railBackground: Color(0xFF090D12),
    workspaceBackground: Color(0xFF090D13),
    rightPanelBackground: Color(0xFF10141B),
    inputFill: Color(0xFF12100E),
    inputBorder: Color(0xFF34302B),
    inputBorderFocused: Color(0xFF5B8DEF),
    border: Color(0x2B94A3B8),
    subtleBorder: Color(0x2E94A3B8),
    selectedBackground: Color(0x2E1E40AF),
    selectedBorder: Color(0x7360A5FA),
    unselectedBackground: Color(0x9E0F172A),
    unselectedBorder: Color(0x2B94A3B8),
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
    assistantBubbleBackground: Color(0xFF111827),
    codeBackground: Color(0xFF05070B),
    teamSelectorBackground: Color(0x2B1E40AF),
    teamSelectorBorder: Color(0x5260A5FA),
    railButtonSelectedBg: Color(0x3D60A5FA),
    railButtonUnselectedBg: Color(0x1F94A3B8),
    railButtonSelectedFg: Color(0xFFDBEAFE),
    railButtonUnselectedFg: Color(0xFFBFBFBF),
    selectedMemberBg: Color(0x2E064E3B),
    unselectedMemberBg: Color(0x9E0F172A),
    typeBadgeApiBg: Color(0x1C60A5FA),
    typeBadgeApiBorder: Color(0x3860A5FA),
    typeBadgeApiText: Color(0xFF93C5FD),
    typeBadgeAccountBg: Color(0x1C34D399),
    typeBadgeAccountBorder: Color(0x3834D399),
    typeBadgeAccountText: Color(0xFFA7F3D0),
    logoGradientStart: Color(0xFF60A5FA),
    logoGradientEnd: Color(0xFF34D399),
    readOnlyFieldBg: Color(0xFF090F1A),
    readOnlyFieldBorder: Color(0x3D94A3B8),
    readOnlyFieldText: Color(0xFFDBEAFE),
    tabBarDivider: Color(0x2494A3B8),
    statBoxBg: Color(0xA60F172A),
    statBoxBorder: Color(0x2994A3B8),
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
    teamSelectorBackground: Color(0xFFE8EDFB),
    teamSelectorBorder: Color(0xFF93B5F5),
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
    extensions: [colors],
  );
}
