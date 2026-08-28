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
///
/// Keep-alive hosts wrap inactive workspace tabs in [TickerMode] off. Those
/// seats still *build* under [TpKeepAliveLayer]; skip cubit [select]s so
/// idle-watch ticks do not rebuild History / compose until the tab is
/// foreground again. [TickerMode.valuesOf] keeps a dependency so becoming
/// foreground rebuilds and re-subscribes.
SessionSeatWorkingBits watchSessionSeatWorking(
  BuildContext context, {
  required String workspaceId,
  required String sessionId,
  required String memberId,
}) {
  MemberPresence presenceOf(MemberPresenceCubit cubit) {
    if (memberId.isEmpty) return const MemberPresence.offline();
    return cubit.state.presence[memberId] ?? const MemberPresence.offline();
  }

  if (!TickerMode.valuesOf(context).enabled) {
    return SessionSeatWorkingBits(
      activeCenterId: context.read<WorkbenchCubit>().centerActiveId(
        workspaceId,
      ),
      sessionWorking: context
          .read<ChatCubit>()
          .state
          .workingSessionIds
          .contains(sessionId),
      presence: presenceOf(context.read<MemberPresenceCubit>()),
    );
  }

  return SessionSeatWorkingBits(
    activeCenterId: context.select<WorkbenchCubit, WorkbenchTabId?>(
      (w) => w.centerActiveId(workspaceId),
    ),
    sessionWorking: context.select<ChatCubit, bool>(
      (c) => c.state.workingSessionIds.contains(sessionId),
    ),
    presence: context.select<MemberPresenceCubit, MemberPresence>(presenceOf),
  );
}
