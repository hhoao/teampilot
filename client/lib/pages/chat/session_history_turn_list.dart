import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../../cubits/session_history_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../services/cli/registry/capabilities/session_history_capability.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';

/// Read-only transcript turns for session history review.
class SessionHistoryTurnList extends StatelessWidget {
  const SessionHistoryTurnList({
    required this.state,
    required this.onRetry,
    super.key,
  });

  final SessionHistoryState state;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    switch (state.status) {
      case SessionHistoryViewStatus.loading:
        return _HistoryStatusPane(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
              SizedBox(height: context.appSpacing.md),
              Text(
                context.l10n.sessionHistoryLoading,
                style: AppTextStyles.of(context).body.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        );
      case SessionHistoryViewStatus.empty:
        return _HistoryStatusPane(
          child: Text(
            context.l10n.sessionHistoryEmpty,
            style: AppTextStyles.of(context).body.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        );
      case SessionHistoryViewStatus.error:
        final detail = state.errorMessage?.trim();
        return _HistoryStatusPane(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                context.l10n.sessionHistoryError,
                style: AppTextStyles.of(context).body.copyWith(
                  color: Theme.of(context).colorScheme.error,
                ),
                textAlign: TextAlign.center,
              ),
              if (detail != null && detail.isNotEmpty) ...[
                SizedBox(height: context.appSpacing.sm),
                Text(
                  detail,
                  style: AppTextStyles.of(context).bodySmall.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
              SizedBox(height: context.appSpacing.md),
              TextButton(
                onPressed: onRetry,
                child: Text(context.l10n.sessionHistoryRetry),
              ),
            ],
          ),
        );
      case SessionHistoryViewStatus.ready:
        return ListView.builder(
          padding: EdgeInsets.fromLTRB(
            context.appSpacing.lg,
            context.appSpacing.md,
            context.appSpacing.lg,
            context.appSpacing.md,
          ),
          itemCount: state.turns.length,
          itemBuilder: (context, index) =>
              _HistoryTurnTile(turn: state.turns[index]),
        );
    }
  }
}

class _HistoryStatusPane extends StatelessWidget {
  const _HistoryStatusPane({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: context.appSpacing.xl),
        child: child,
      ),
    );
  }
}

class _HistoryTurnTile extends StatelessWidget {
  const _HistoryTurnTile({required this.turn});

  final SessionHistoryTurn turn;

  @override
  Widget build(BuildContext context) {
    final spacing = context.appSpacing;
    final cs = Theme.of(context).colorScheme;
    final styles = AppTextStyles.of(context);

    if (turn.role == SessionHistoryRole.tool) {
      final title = turn.toolName?.trim().isNotEmpty == true
          ? turn.toolName!.trim()
          : context.l10n.sessionHistoryToolTurn;
      return Padding(
        padding: EdgeInsets.only(bottom: spacing.sm),
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            initiallyExpanded: !turn.collapsedByDefault,
            tilePadding: EdgeInsets.symmetric(horizontal: spacing.sm),
            childrenPadding: EdgeInsets.fromLTRB(
              spacing.sm,
              0,
              spacing.sm,
              spacing.sm,
            ),
            title: Text(
              title,
              style: styles.bodySmall.copyWith(
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: MarkdownBody(data: turn.markdown),
              ),
            ],
          ),
        ),
      );
    }

    final l10n = context.l10n;
    final label = switch (turn.role) {
      SessionHistoryRole.user => l10n.sessionHistoryRoleUser,
      SessionHistoryRole.assistant => l10n.sessionHistoryRoleAssistant,
      SessionHistoryRole.system => l10n.sessionHistoryRoleSystem,
      SessionHistoryRole.tool => l10n.sessionHistoryToolTurn,
    };

    return Padding(
      padding: EdgeInsets.only(bottom: spacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            label,
            style: styles.bodySmall.copyWith(
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: spacing.xs),
          MarkdownBody(data: turn.markdown),
        ],
      ),
    );
  }
}
