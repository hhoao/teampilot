import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../l10n/l10n_extensions.dart';

export '../../l10n/app_localizations.dart' show AppLocalizations;

typedef _L10n = AppLocalizations;

/// Builder-only status chrome rendered above the session content inside
/// `ChatWorkbench` for `SessionPurpose.teamGeneration` sessions.
///
/// Shows the durable workflow phase, an expandable plan preview (never
/// tokens/credentials/raw probe output/full paths), and phase-specific
/// actions: Cancel (pre-commit), Retry / Continue setup (failures), and the
/// ambiguous-delivery trio.
class TeamGenerationBuilderStatus extends StatelessWidget {
  const TeamGenerationBuilderStatus({
    super.key,
    required this.phase,
    this.teamName,
    this.previewLines = const [],
    this.profilePersisted = false,
    this.errorCode,
    this.onRetry,
    this.onCancel,
    this.onOpenLeadSession,
    this.onConfirmArrived,
    this.onSendAgain,
  });

  /// Durable [TeamGenerationPhase] name (e.g. `probing`, `failed`).
  final String phase;

  /// Frozen generated team name shown in the preview header once validated.
  final String? teamName;

  /// Bounded preview lines (role · preset · target summary rows).
  final List<String> previewLines;

  /// True after the profile receipt succeeded; Cancel becomes unavailable.
  final bool profilePersisted;

  /// Sanitized `TeamGenerationError.code` driving remediation copy.
  final String? errorCode;

  final VoidCallback? onRetry;
  final VoidCallback? onCancel;
  final VoidCallback? onOpenLeadSession;
  final VoidCallback? onConfirmArrived;
  final VoidCallback? onSendAgain;

  static const _preCommitPhaseSet = {'created', 'probing', 'planning', 'validating'};
  static const _postCommitPhases = {
    'committing',
    'launching',
    'delivering',
    'delivered',
    'cleaning',
  };

  bool get _isFailed => phase == 'failed';

  bool get _isAmbiguousDelivery => errorCode == 'prompt_delivery_unknown';

  static bool _preCommitContains(String phase) =>
      _preCommitPhaseSet.contains(phase);

  bool get _canCancel =>
      !profilePersisted &&
      !_postCommitPhases.contains(phase) &&
      !_isAmbiguousDelivery;

  @override
  Widget build(BuildContext context) {
    final styles = TpTextStyles.of(context);
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              TpStatusBadge(
                label: l10n.teamGenerateBuilderTitle,
                tone: _isFailed
                    ? TpStatusBadgeTone.warning
                    : TpStatusBadgeTone.neutral,
                icon: _isFailed ? Icons.warning_amber_outlined : null,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _phaseText(l10n),
                  style: styles.mdMedium,
                  semanticsLabel: _phaseText(l10n),
                ),
              ),
            ],
          ),
          if (previewLines.isNotEmpty) ...[
            const SizedBox(height: 8),
            if (teamName != null)
              Text(teamName!, style: styles.mdSemibold),
            for (final line in previewLines)
              Text(line, style: styles.smMedium),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (_isAmbiguousDelivery) ...[
                TpButton(
                  variant: TpButtonVariant.ghost,
                  onPressed: onOpenLeadSession,
                  child: Text(l10n.teamGenerateOpenLeadSession),
                ),
                TpButton(
                  variant: TpButtonVariant.ghost,
                  onPressed: onConfirmArrived,
                  child: Text(l10n.teamGenerateDeliveryArrived),
                ),
                TpButton(
                  variant: TpButtonVariant.ghost,
                  onPressed: onSendAgain,
                  child: Text(l10n.teamGenerateDeliverySendAgain),
                ),
              ] else ...[
                if (_isFailed)
                  TpButton(
                    variant: TpButtonVariant.ghost,
                    onPressed: onRetry,
                    child: Text(
                      profilePersisted
                          ? l10n.teamGenerateContinueSetup
                          : l10n.teamGenerateRetry,
                    ),
                  ),
                if (_canCancel)
                  TpButton(
                    variant: TpButtonVariant.ghost,
                    onPressed: onCancel,
                    child: Text(l10n.teamGenerateCancel),
                  ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  String _phaseText(_L10n l10n) => switch (phase) {
        'created' => l10n.teamGeneratePhaseCreated,
        'probing' => l10n.teamGeneratePhaseProbing,
        'planning' => l10n.teamGeneratePhasePlanning,
        'validating' => l10n.teamGeneratePhaseValidating,
        'committing' => l10n.teamGeneratePhaseCommitting,
        'launching' => l10n.teamGeneratePhaseLaunching,
        'delivering' => l10n.teamGeneratePhaseDelivering,
        'delivered' || 'cleaning' => l10n.teamGeneratePhaseCleaning,
        'failed' => l10n.teamGeneratePhaseFailed,
        _ => l10n.teamGeneratePhaseCreated,
      };
}
