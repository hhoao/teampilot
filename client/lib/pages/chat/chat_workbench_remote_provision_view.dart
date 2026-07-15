import 'package:flutter/material.dart';

import '../../l10n/l10n_extensions.dart';
import '../../models/member_remote_provision_progress.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/cli_install_progress_panel.dart';

/// Full-pane overlay while an SSH member's remote CLI/workspace is provisioning.
class ChatWorkbenchRemoteProvisionView extends StatelessWidget {
  const ChatWorkbenchRemoteProvisionView({
    super.key,
    required this.progress,
    required this.memberLabel,
  });

  final MemberRemoteProvisionProgress progress;
  final String memberLabel;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final styles = AppTextStyles.of(context);
    final host = progress.hostLabel.trim();
    final title = host.isEmpty
        ? memberLabel
        : l10n.sessionRemoteProvisionTitle(memberLabel, host);

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                title,
                textAlign: TextAlign.center,
                style: styles.mdMedium,
              ),
              const SizedBox(height: 16),
              if (progress.hasFailed) ...[
                Icon(Icons.error_outline, color: cs.error, size: 36),
                const SizedBox(height: 12),
                Text(
                  l10n.sessionRemoteProvisionFailed,
                  textAlign: TextAlign.center,
                  style: styles.mdMedium.copyWith(color: cs.error),
                ),
                const SizedBox(height: 8),
                SelectableText(
                  progress.error!.trim(),
                  textAlign: TextAlign.center,
                  style: styles.mutedSm,
                ),
              ] else
                CliInstallProgressPanel(
                  phase: progress.phase,
                  logLines: [
                    if ((progress.detail ?? '').trim().isNotEmpty)
                      progress.detail!.trim(),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}
