import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/chat_cubit.dart';
import '../../cubits/member_presence_cubit.dart';
import '../../models/member_presence.dart';
import '../../models/app_session.dart';
import '../../models/team_config.dart';
import '../../services/follow_up/follow_up_queue.dart';
import '../../services/session/history_seat_key.dart';
import 'follow_up_queue_strip.dart';

/// Finder key for the terminal follow-up queue strip (no compose field).
const Key kTerminalFollowUpComposeKey = ValueKey('terminal-follow-up-compose');

/// Terminal only mirrors an existing queue — enqueue happens from History.
bool shouldShowTerminalFollowUpStrip(FollowUpQueue queue) =>
    queue.items.isNotEmpty;

/// Docked queue strip above the terminal (manage / Resume only; no input).
class TerminalFollowUpCompose extends StatelessWidget {
  const TerminalFollowUpCompose({
    required this.session,
    required this.selectedMemberId,
    super.key,
  });

  final AppSession session;
  final String selectedMemberId;

  String get _shellMemberId => shellMemberIdForHistory(
    sessionId: session.sessionId,
    selectedMemberId: selectedMemberId,
  );

  String get _followUpSeatKey =>
      followUpSeatKey(session.sessionId, _shellMemberId);

  @override
  Widget build(BuildContext context) {
    final chat = context.read<ChatCubit>();

    return StreamBuilder<FollowUpQueue>(
      stream: chat.followUpQueue.watch(_followUpSeatKey),
      initialData: chat.followUpQueue.queueFor(_followUpSeatKey),
      builder: (context, snapshot) {
        final queue = snapshot.data ?? const FollowUpQueue();
        if (!shouldShowTerminalFollowUpStrip(queue)) {
          return const SizedBox.shrink();
        }

        final spacing = context.tpSpacing;
        final cs = Theme.of(context).colorScheme;

        return Material(
          key: kTerminalFollowUpComposeKey,
          color: cs.surface.withValues(alpha: 0.94),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              spacing.md,
              spacing.sm,
              spacing.md,
              spacing.sm,
            ),
            child: FollowUpQueueStrip(
              queue: queue,
              onDelete: (id) =>
                  chat.followUpQueue.remove(_followUpSeatKey, id),
              onEdit: (id, content) =>
                  chat.followUpQueue.edit(_followUpSeatKey, id, content),
              onMoveUp: (id) =>
                  chat.followUpQueue.moveUp(_followUpSeatKey, id),
              onResume: () => unawaited(
                chat.resumeFollowUpQueue(session.sessionId, _shellMemberId),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Keeps follow-up drain in sync with seat working while Terminal is visible.
class TerminalFollowUpComposeHost extends StatelessWidget {
  const TerminalFollowUpComposeHost({
    required this.session,
    required this.selectedMemberId,
    this.team,
    super.key,
  });

  final AppSession session;
  final String selectedMemberId;

  /// Unused for strip-only chrome; kept so call sites stay stable.
  final TeamProfile? team;

  @override
  Widget build(BuildContext context) {
    // Rebuild when this session working or bus presence changes. Scoped to
    // [session.sessionId] so background sessions do not rebuild every host on
    // unrelated working/activation changes.
    context.select<ChatCubit, bool>(
      (c) =>
          c.state.activeSessionId == session.sessionId ||
          c.state.workingSessionIds.contains(session.sessionId),
    );
    context.select<MemberPresenceCubit, Map<String, MemberPresence>>(
      (c) => c.state.presence,
    );

    final shellMemberId = shellMemberIdForHistory(
      sessionId: session.sessionId,
      selectedMemberId: selectedMemberId,
    );

    return MultiBlocListener(
      listeners: [
        BlocListener<ChatCubit, ChatState>(
          listenWhen: (previous, current) =>
              previous.workingSessionIds != current.workingSessionIds,
          listener: (context, _) {
            final cubit = context.read<ChatCubit>();
            cubit.notifyFollowUpMemberWorking(
              session.sessionId,
              shellMemberId,
              working: cubit.isMemberWorking(
                session.sessionId,
                shellMemberId,
              ),
            );
          },
        ),
        BlocListener<MemberPresenceCubit, MemberPresenceState>(
          listenWhen: (previous, current) =>
              previous.presence != current.presence,
          listener: (context, _) {
            final cubit = context.read<ChatCubit>();
            cubit.notifyFollowUpMemberWorking(
              session.sessionId,
              shellMemberId,
              working: cubit.isMemberWorking(
                session.sessionId,
                shellMemberId,
              ),
            );
          },
        ),
      ],
      child: TerminalFollowUpCompose(
        session: session,
        selectedMemberId: selectedMemberId,
      ),
    );
  }
}
