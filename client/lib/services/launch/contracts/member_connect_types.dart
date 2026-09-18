import '../../../cubits/chat/model/chat_tab.dart';
import '../../../models/app_session.dart';
import '../../../models/team_config.dart';
import '../../../models/workspace.dart';
import '../connect/session_connect_job.dart';

/// Schedules a per-member PTY connect on [tab].
///
/// Shared by the launch bundle, the lifecycle connect coordinator, and the SSH
/// profile reconnect path — all three receive it as a constructor dependency
/// from `SessionLaunchService`. Kept here rather than on any one consumer so
/// that no consumer has to import another.
typedef ScheduleMemberConnectFn =
    void Function(
      TeamProfile team,
      TeamMemberConfig member,
      ChatTab tab, {
      bool selectMember,
      LaunchReason? reason,
    });

typedef SessionForMemberConnectFn =
    AppSession? Function(ChatTab tab, TeamProfile team);

typedef WorkspaceByIdFn = Workspace? Function(String workspaceId);
