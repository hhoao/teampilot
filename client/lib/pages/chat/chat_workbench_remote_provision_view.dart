import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../l10n/l10n_extensions.dart';
import '../../models/member_remote_provision_progress.dart';
import '../../services/cli/installer_types.dart';
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
    final styles = TpTextStyles.of(context);
    final host = _friendlyHostLabel(progress.hostLabel);
    final member = _friendlyMemberLabel(memberLabel);
    final title = _title(l10n, member: member, host: host);
    final detail = progress.detail?.trim() ?? '';
    final showDetail = isUserFacingCliInstallDetail(detail);

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
                  logLines: [if (showDetail) detail],
                ),
            ],
          ),
        ),
      ),
    );
  }

  static String _title(
    AppLocalizations l10n, {
    required String member,
    required String host,
  }) {
    if (member.isNotEmpty && host.isNotEmpty) {
      return l10n.sessionRemoteProvisionTitle(member, host);
    }
    if (host.isNotEmpty) {
      return l10n.sessionRemoteProvisionPreparingOnHost(host);
    }
    if (member.isNotEmpty) return member;
    return l10n.sessionRemoteProvisionPreparing;
  }

  /// Drop raw target ids (`ssh:<uuid>`) and empty strings.
  static String _friendlyHostLabel(String raw) {
    final host = raw.trim();
    if (host.isEmpty) return '';
    if (host.startsWith('ssh:') || host.startsWith('termux:')) return '';
    if (_looksLikeUuid(host)) return '';
    return host;
  }

  /// Personal sessions use sessionId as memberId — don't show UUIDs.
  static String _friendlyMemberLabel(String raw) {
    final member = raw.trim();
    if (member.isEmpty || _looksLikeUuid(member)) return '';
    return member;
  }

  static final _uuidPattern = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  static bool _looksLikeUuid(String value) => _uuidPattern.hasMatch(value);
}
