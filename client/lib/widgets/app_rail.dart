import 'package:flutter/material.dart';

import '../utils/app_keys.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';

enum AppSection { chat, runs, config }

class AppRail extends StatelessWidget {
  const AppRail({required this.selected, required this.onSelected, super.key});

  final AppSection selected;
  final ValueChanged<AppSection> onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final l10n = context.l10n;
    return Container(
      width: 64,
      color: colors.railBackground,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      child: Column(
        children: [
          _Logo(),
          const SizedBox(height: 14),
          _RailButton(
            key: AppKeys.appRailChatButton,
            selected: selected == AppSection.chat,
            icon: Icons.chat_bubble_outline,
            label: l10n.appRailChat,
            onPressed: () => onSelected(AppSection.chat),
          ),
          const SizedBox(height: 10),
          _RailButton(
            key: AppKeys.appRailRunsButton,
            selected: selected == AppSection.runs,
            icon: Icons.play_circle_outline,
            label: l10n.appRailRuns,
            onPressed: () => onSelected(AppSection.runs),
          ),
          const SizedBox(height: 10),
          _RailButton(
            key: AppKeys.appRailConfigButton,
            selected: selected == AppSection.config,
            icon: Icons.tune_outlined,
            label: l10n.appRailConfig,
            onPressed: () => onSelected(AppSection.config),
          ),
        ],
      ),
    );
  }
}

class _Logo extends StatelessWidget {
  const _Logo();

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        gradient: LinearGradient(
          colors: [colors.logoGradientStart, colors.logoGradientEnd],
        ),
      ),
    );
  }
}

class _RailButton extends StatelessWidget {
  const _RailButton({
    required this.selected,
    required this.icon,
    required this.label,
    required this.onPressed,
    super.key,
  });

  final bool selected;
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Tooltip(
      message: label,
      child: IconButton(
        style: IconButton.styleFrom(
          backgroundColor: selected
              ? colors.railButtonSelectedBg
              : colors.railButtonUnselectedBg,
          foregroundColor: selected
              ? colors.railButtonSelectedFg
              : colors.railButtonUnselectedFg,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
        ),
        onPressed: onPressed,
        icon: Icon(icon, size: 20),
      ),
    );
  }
}
