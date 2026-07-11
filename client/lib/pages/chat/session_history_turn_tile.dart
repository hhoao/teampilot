import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../../l10n/l10n_extensions.dart';
import '../../services/cli/registry/capabilities/session_history_capability.dart';
import '../../theme/app_markdown_style_sheet.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../home_workspace/workspace/workspace_chat_landing_palette.dart';

/// Chat-style bubble for one history turn.
class SessionHistoryTurnTile extends StatelessWidget {
  const SessionHistoryTurnTile({required this.turn, super.key});

  final SessionHistoryTurn turn;

  @override
  Widget build(BuildContext context) {
    final spacing = context.appSpacing;
    return Padding(
      padding: EdgeInsets.only(bottom: spacing.md),
      child: switch (turn.role) {
        SessionHistoryRole.user => _UserBubble(turn: turn),
        SessionHistoryRole.assistant => _AssistantBubble(turn: turn),
        SessionHistoryRole.system => _SystemBubble(turn: turn),
        SessionHistoryRole.tool => _ToolBubble(turn: turn),
      },
    );
  }
}

MarkdownBody _historyMarkdown(BuildContext context, String data) {
  return MarkdownBody(
    data: data,
    styleSheet: buildAppMarkdownStyleSheet(Theme.of(context)),
  );
}

class _UserBubble extends StatelessWidget {
  const _UserBubble({required this.turn});

  final SessionHistoryTurn turn;

  @override
  Widget build(BuildContext context) {
    final palette = WorkspaceChatLandingPalette(Theme.of(context).colorScheme);
    final spacing = context.appSpacing;
    final maxWidth = MediaQuery.sizeOf(context).width * 0.82;

    return Align(
      alignment: Alignment.centerRight,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: palette.chipFill,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: spacing.md,
              vertical: spacing.sm + 2,
            ),
            child: _historyMarkdown(context, turn.markdown),
          ),
        ),
      ),
    );
  }
}

class _AssistantBubble extends StatelessWidget {
  const _AssistantBubble({required this.turn});

  final SessionHistoryTurn turn;

  @override
  Widget build(BuildContext context) {
    final palette = WorkspaceChatLandingPalette(Theme.of(context).colorScheme);
    final spacing = context.appSpacing;
    final styles = AppTextStyles.of(context);
    final maxWidth = MediaQuery.sizeOf(context).width * 0.96;

    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: spacing.xs),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.l10n.sessionHistoryRoleAssistant,
                style: styles.mdSemiboldColored(palette.muted),
              ),
              SizedBox(height: spacing.xs),
              _historyMarkdown(context, turn.markdown),
            ],
          ),
        ),
      ),
    );
  }
}

class _SystemBubble extends StatelessWidget {
  const _SystemBubble({required this.turn});

  final SessionHistoryTurn turn;

  @override
  Widget build(BuildContext context) {
    final palette = WorkspaceChatLandingPalette(Theme.of(context).colorScheme);
    final spacing = context.appSpacing;
    final styles = AppTextStyles.of(context);

    return Center(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: palette.chipFill.withValues(alpha: 0.65),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: spacing.md,
            vertical: spacing.xs + 2,
          ),
          child: Text(
            turn.markdown.trim(),
            style: styles.smColored(palette.muted),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}

class _ToolBubble extends StatelessWidget {
  const _ToolBubble({required this.turn});

  final SessionHistoryTurn turn;

  @override
  Widget build(BuildContext context) {
    final palette = WorkspaceChatLandingPalette(Theme.of(context).colorScheme);
    final spacing = context.appSpacing;
    final styles = AppTextStyles.of(context);
    final title = turn.toolName?.trim().isNotEmpty == true
        ? turn.toolName!.trim()
        : context.l10n.sessionHistoryToolTurn;

    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.92,
        ),
        child: Material(
          color: palette.elevated.withValues(alpha: 0.7),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: palette.border.withValues(alpha: 0.6)),
          ),
          clipBehavior: Clip.antiAlias,
          child: Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              initiallyExpanded: !turn.collapsedByDefault,
              tilePadding: EdgeInsets.symmetric(horizontal: spacing.sm),
              childrenPadding: EdgeInsets.fromLTRB(
                spacing.md,
                0,
                spacing.md,
                spacing.sm,
              ),
              leading: Icon(
                Icons.terminal_rounded,
                size: 18,
                color: palette.muted,
              ),
              title: Text(
                title,
                style: styles.mdSemiboldColored(palette.muted),
              ),
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: _historyMarkdown(context, turn.markdown),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
