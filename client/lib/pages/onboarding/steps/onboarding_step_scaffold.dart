import 'package:flutter/material.dart';

import '../../../theme/app_text_styles.dart';

/// Shared onboarding step chrome: pinned title/subtitle, scrollable body.
///
/// Hosted in the wizard's fixed max-height viewport. Title stays put; [body]
/// scrolls in the remaining space. Content stays top-aligned under the header.
class OnboardingStepScaffold extends StatelessWidget {
  const OnboardingStepScaffold({
    super.key,
    required this.title,
    required this.subtitle,
    required this.body,
    this.headerTrailing,
  });

  final String title;
  final String subtitle;
  final Widget body;
  final Widget? headerTrailing;

  @override
  Widget build(BuildContext context) {
    final header = <Widget>[
      Text(title, style: AppTextStyles.of(context).display),
      const SizedBox(height: 8),
      Text(subtitle, style: AppTextStyles.of(context).mutedMd),
      if (headerTrailing != null) ...[
        const SizedBox(height: 12),
        headerTrailing!,
      ],
      const SizedBox(height: 16),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        if (!constraints.hasBoundedHeight) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [...header, body],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ...header,
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(bottom: 8),
                child: body,
              ),
            ),
          ],
        );
      },
    );
  }
}
