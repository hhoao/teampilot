import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/chat_cubit.dart';
import '../../cubits/mailbox_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/team_config.dart';
import '../../services/team_bus/bus_feed_entry.dart';
import '../../services/team_bus/team_bus.dart';

/// Live full-team team-bus message feed. Polling is owned by [RightToolsPanel];
/// tapping a row jumps to the relevant member's chat tab.
class MailboxPanel extends StatelessWidget {
  const MailboxPanel({required this.team, required this.cwd, super.key});

  final TeamProfile team;
  final String cwd;

  void _jumpTo(BuildContext context, BusFeedEntry entry) {
    final targetId =
        entry.from == TeamBus.userSenderId ? entry.to : entry.from;
    if (targetId == TeamBus.userSenderId || targetId == '*') return;
    final matches = team.members.where((m) => m.id == targetId);
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
    final entries = context.watch<MailboxCubit>().state.entries;
    if (entries.isEmpty) {
      return Center(
        child: Text(l10n.mailboxEmpty,
            style: TextStyle(color: cs.onSurfaceVariant)),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 6),
      itemCount: entries.length,
      itemBuilder: (context, i) {
        final e = entries[entries.length - 1 - i]; // newest first
        return ListTile(
          leading: Icon(
            e.isUnread
                ? Icons.mark_email_unread_outlined
                : Icons.email_outlined,
            size: 18,
            color: e.isUnread ? cs.primary : cs.onSurfaceVariant,
          ),
          title: Text('${e.from} → ${e.to}',
              style: Theme.of(context).textTheme.labelSmall),
          subtitle:
              Text(e.content, maxLines: 2, overflow: TextOverflow.ellipsis),
          onTap: () => _jumpTo(context, e),
        );
      },
    );
  }
}
