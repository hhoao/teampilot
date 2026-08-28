import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/chat_cubit.dart';
import '../../cubits/member_presence_cubit.dart';
import '../../cubits/workbench/workbench_cubit.dart';
import '../../cubits/workbench/workbench_tab.dart';
import '../../models/member_presence.dart';

/// This seat's working / presence / active-tab bits.
///
/// Subscribe via [watchSessionSeatWorking] so idle-watch ticks for **other**
/// sessions do not rebuild History / compose.
class SessionSeatWorkingBits {
  const SessionSeatWorkingBits({
    required this.sessionWorking,
    required this.presence,
    required this.activeCenterId,
  });

  final bool sessionWorking;
  final MemberPresence presence;
  final WorkbenchTabId? activeCenterId;
}

/// Leaf-safe subscriptions for this session seat. Call from `build`.
SessionSeatWorkingBits watchSessionSeatWorking(
  BuildContext context, {
  required String workspaceId,
  required String sessionId,
  required String memberId,
}) {
  return SessionSeatWorkingBits(
    activeCenterId: context.select<WorkbenchCubit, WorkbenchTabId?>(
      (w) => w.centerActiveId(workspaceId),
    ),
    sessionWorking: context.select<ChatCubit, bool>(
      (c) => c.state.workingSessionIds.contains(sessionId),
    ),
    presence: context.select<MemberPresenceCubit, MemberPresence>(
      (c) => memberId.isEmpty
          ? const MemberPresence.offline()
          : (c.state.presence[memberId] ?? const MemberPresence.offline()),
    ),
  );
}
