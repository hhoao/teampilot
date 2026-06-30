import 'package:flutter/material.dart';

import '../../theme/app_text_styles.dart';
import '../../widgets/settings/workspace_settings_widgets.dart';

class TeamConfigCard extends StatelessWidget {
  const TeamConfigCard({super.key, required this.child, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: padding ?? const EdgeInsets.all(18),
      decoration: workspaceCardDecoration(cs, radius: 12),
      child: child,
    );
  }
}

class TeamConfigCardHeader extends StatelessWidget {
  const TeamConfigCardHeader({super.key, required this.title, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textBase = cs.onSurface;
    final titleWidget = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: AppTextStyles.of(
            context,
          ).sectionTitle.copyWith(fontWeight: FontWeight.w800, color: textBase),
        ),
      ],
    );
    if (trailing == null) return titleWidget;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: titleWidget),
        trailing!,
      ],
    );
  }
}
