import 'package:flutter/material.dart';

import '../../../l10n/l10n_extensions.dart';
import '../../../theme/app_text_styles.dart';

/// Sidebar callout when a mixed workspace is opened under a personal identity.
class MixedWorkspacePersonalLaunchBanner extends StatelessWidget {
  const MixedWorkspacePersonalLaunchBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final styles = AppTextStyles.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: cs.tertiaryContainer.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: cs.tertiary.withValues(alpha: 0.35)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.hub_outlined, size: 18, color: cs.tertiary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  context.l10n.mixedWorkspacePersonalLaunchBlockedHint,
                  style: styles.bodySmall.copyWith(color: cs.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
