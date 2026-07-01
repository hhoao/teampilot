import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/board_cubit.dart';
import '../../cubits/chat_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/board_column.dart';
import '../../models/team_config.dart';
import '../../services/team_bus/tasks/team_task.dart';

/// Live read-only task board for a mixed-mode team. Polling is owned by
/// [RightToolsPanel]. Tapping a claimed card opens the assignee's chat tab.
class BoardPanel extends StatelessWidget {
  const BoardPanel({required this.team, required this.cwd, super.key});

  final TeamProfile team;
  final String cwd;

  String _memberName(String? id) {
    if (id == null) return '';
    final m = team.members.cast<TeamMemberConfig?>().firstWhere(
          (m) => m?.id == id,
          orElse: () => null,
        );
    return m?.name ?? id;
  }

  void _openAssignee(BuildContext context, String? assigneeId) {
    if (assigneeId == null) return;
    final matches = team.members.where((m) => m.id == assigneeId);
    if (matches.isEmpty) return;
    unawaited(context.read<ChatCubit>().openMemberTab(
          team,
          matches.first,
          workspaceCwd: cwd,
        ));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final state = context.watch<BoardCubit>().state;

    if (state.total == 0) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.view_kanban_outlined,
                size: 36, color: cs.onSurfaceVariant),
            const SizedBox(height: 8),
            Text(l10n.boardEmpty,
                style: TextStyle(color: cs.onSurfaceVariant)),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 4),
      children: [
        for (final column in BoardColumn.values)
          _ColumnSection(
            column: column,
            cards: state.columns[column] ?? const [],
            memberName: _memberName,
            onTapCard: (id) => _openAssignee(context, id),
          ),
      ],
    );
  }
}

class _ColumnSection extends StatelessWidget {
  const _ColumnSection({
    required this.column,
    required this.cards,
    required this.memberName,
    required this.onTapCard,
  });

  final BoardColumn column;
  final List<BoardCard> cards;
  final String Function(String?) memberName;
  final void Function(String?) onTapCard;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final tt = Theme.of(context).textTheme;

    final (icon, label) = switch (column) {
      BoardColumn.pending =>
        (Icons.hourglass_top_outlined, l10n.boardPending),
      BoardColumn.claimed =>
        (Icons.play_circle_outline, l10n.boardClaimed),
      BoardColumn.done => (Icons.check_circle_outline, l10n.boardDone),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Row(
            children: [
              Icon(icon, size: 14, color: cs.onSurfaceVariant),
              const SizedBox(width: 6),
              Text(label,
                  style: tt.labelSmall?.copyWith(
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w600)),
              const SizedBox(width: 6),
              Text('(${cards.length})',
                  style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
            ],
          ),
        ),
        for (final card in cards)
          _CardTile(
            card: card,
            memberName: memberName(card.assigneeId),
            onTap: card.column == BoardColumn.claimed
                ? () => onTapCard(card.assigneeId)
                : null,
          ),
        const Divider(height: 1, thickness: 1),
      ],
    );
  }
}

class _CardTile extends StatelessWidget {
  const _CardTile({
    required this.card,
    required this.memberName,
    required this.onTap,
  });

  final BoardCard card;
  final String memberName;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final isError =
        card.status == TaskStatus.failed || card.status == TaskStatus.cancelled;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('#${card.seq}',
                style: tt.labelSmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontFeatures: const [FontFeature.tabularFigures()])),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(card.title,
                      maxLines: 2, overflow: TextOverflow.ellipsis),
                  if (memberName.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text('› $memberName',
                        style: tt.labelSmall
                            ?.copyWith(color: cs.onSurfaceVariant)),
                  ],
                ],
              ),
            ),
            if (card.column == BoardColumn.done)
              Icon(
                card.status == TaskStatus.done
                    ? Icons.check
                    : card.status == TaskStatus.failed
                        ? Icons.close
                        : Icons.remove,
                size: 14,
                color: isError ? cs.error : cs.onSurfaceVariant,
              ),
          ],
        ),
      ),
    );
  }
}
