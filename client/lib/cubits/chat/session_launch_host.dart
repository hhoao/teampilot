import 'package:flutter_alacritty/flutter_alacritty.dart';

import '../../models/app_session.dart';
import '../../models/team_config.dart';
import '../../repositories/session_repository.dart';
import '../../services/cli/registry/cli_tool_registry.dart';
import '../../services/team/team_config_launch_validator.dart';
import '../../services/launch/session_connect_orchestrator.dart';
import '../../services/launch/workspace_provision_coordinator.dart';
import '../../services/session/session_lifecycle_service.dart';
import '../../services/team_bus/mcp/teammate_bus_mcp_gateway.dart';
import '../../services/team_bus/remote/remote_bus_binding_resolver.dart';
import 'chat_session_shell_factory.dart';
import 'model/chat_state.dart';
import 'model/chat_tab.dart';
import 'session_data_store.dart';
import 'tab_member_materializer.dart';
import 'tab_session_runtime_coordinator.dart';
import 'tab_team_bus_coordinator.dart';
import 'chat_tab_store.dart';

/// Connect-state transitions owned by [ChatCubit] (via [ChatConnectStateMixin]).
abstract interface class SessionConnectStatePort {
  void beginSessionConnect(String sessionId);
  void failSessionConnect(String sessionId, String rawMessage);
  void finishSessionConnect(String sessionId);
  void clearLaunchError(String sessionId);
  void setLaunchError(String sessionId, String rawMessage);
  void emitLaunchWarnings(List<String> warnings);
  void updateTabRunning(String tabId);
}

/// Session snapshot writes routed through the cubit emit path.
abstract interface class SessionSnapshotPort {
  void appendSessionSnapshot(AppSession session);
  void replaceSessionSnapshot(AppSession session);
  void removeSessionSnapshot(String sessionId);
  void emitSnapshot(ChatDataSnapshot snapshot);
}

/// Seam [SessionLaunchService] uses to read/emit ChatState and reach the other
/// collaborators. Implemented by ChatCubit, which stays the sole emit owner
/// (the service routes every state write through [applyState] / the connect
/// state-machine methods).
abstract interface class SessionLaunchHost
    implements SessionConnectStatePort, SessionSnapshotPort {
  ChatState get state;
  bool get isClosed;

  /// Single emit entry point (wraps the cubit's protected emit).
  void applyState(ChatState next);
  void refreshActiveWorkspaceTabs();
  void closeSessionTab(String sessionId);
  void emitTeamConfigValidation(TeamConfigValidation validation);

  // Cubit-owned facade methods the launch flow drives.
  void selectMember(String memberId);
  Future<void> renameSession(
    SessionRepository repo,
    String sessionId,
    String newName,
  );
  Future<void> loadWorkspaceData(SessionRepository repo);
  void pushPresenceTarget();

  ChatTab? get activeTab;
  set activeTeam(TeamProfile? team);

  // Collaborators.
  ChatTabStore get tabStore;
  ChatSessionShellFactory get shellFactory;
  TabSessionRuntimeCoordinator get sessionRuntime;
  TabTeamBusCoordinator get teamBus;
  TabMemberMaterializer get memberMaterializer;
  SessionLifecycleService get lifecycle;
  SessionDataStore get dataStore;

  // Resolvers.
  SessionRepository? get sessionRepository;
  PostFrameScheduler get postFrameScheduler;
  bool Function()? get autoLaunchAllMembersOnConnect;

  /// P3b (#1): resolves a remote member's reverse-tunnel bus binding. Null when
  /// remote-member-over-tunnel is not wired (then all members use local
  /// transport — pre-P3b behavior).
  RemoteBusBindingResolver? get remoteBusResolver;

  SessionConnectOrchestrator get sessionConnect;

  TeammateBusMcpGateway get teammateBusMcpGateway;

  /// Exposes workspace Phase A for team / mixed off-home paths.
  WorkspaceProvisionCoordinator get workspaceProvision;

  /// CLI registry for lifecycle gating and tool capabilities at connect time.
  CliToolRegistry get cliRegistry;

  Future<TeamProfile?> teamProfileById(String teamId);

  /// SSH root-sandbox env injection preference for a runtime target.
  Future<bool> isRootSandboxEnvOptIn(String targetId);

  /// Terminal theme for member PTY spawn (COLORFGBG / Claude `theme: auto`).
  /// Null skips apply — tests and early bootstrap may omit it.
  TerminalTheme? resolveTerminalThemeForLaunch();
}
