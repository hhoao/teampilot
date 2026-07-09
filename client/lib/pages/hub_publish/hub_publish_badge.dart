import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/l10n_extensions.dart';
import '../../services/hub_publish/hub_publish_record_store.dart';
import '../team_hub/team_hub_cards.dart';

/// Compact “PR open” chip for My Teams / My Experts cards.
class HubPublishBadge extends StatelessWidget {
  const HubPublishBadge({
    super.key,
    required this.record,
  });

  final HubPublishRecord record;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: () async {
        final uri = Uri.tryParse(record.prUrl);
        if (uri == null) return;
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      },
      child: TeamStatChip(
        icon: Icons.merge_outlined,
        label: l10n.hubPublishBadgePrOpen,
        accent: cs.primary,
        tooltip: l10n.hubPublishOpenPr,
      ),
    );
  }
}
