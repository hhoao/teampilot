import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../cubits/chat/chat_tab_store.dart';
import '../../cubits/chat/model/chat_state.dart';
import '../../cubits/chat/model/chat_tab.dart';
import '../../cubits/chat/model/session_open_request.dart';
import '../../cubits/chat/model/session_open_status.dart';
import '../../cubits/chat/session_launch_host.dart';
import '../../models/app_session.dart';
import '../../models/team_config.dart';
import '../../models/workspace.dart';
import '../../services/terminal/terminal_session.dart';
import 'contracts/launch_operation.dart';
import 'contracts/launch_outcome.dart';
import 'contracts/member_connect_types.dart';
import 'session/session_default_materializer.dart';
import 'tab/session_launch_connect_prep_runner.dart';
import 'connect/member_connect_stage.dart';
import 'session/session_launch_pipeline.dart';
import 'session/session_open_router.dart';
import 'session/session_launch_workspace_index.dart';
import 'tab/session_tab_connect_prep.dart';
import 'tab/session_tab_surface_coordinator.dart';

/// Dependencies required to wire tab surface, materializer, and pipeline.
class SessionLaunchBundleDeps {
  const SessionLaunchBundleDeps({
    required this.host,
    required this.tabStore,
    required this.state,
    required this.workspaceIndex,
    required this.workspaceById,
    required this.prepCallbacks,
    required this.shouldAutoConnect,
    required this.scheduleShellConnect,
    required this.rollbackStagedLaunch,
    required this.installTeamRuntimeIfNeeded,
    required this.scheduleMemberConnect,
    required this.disconnectSession,
    required this.ensureSession,
    required this.appendLocalTab,
    required this.ensureActiveSessionTab,
    required this.resetTeamConfigValidationSurface,
    required this.scheduleTeamConfigValidation,
    required this.activeTab,
    required this.autoLaunchAllMembersOnConnect,
    required this.isTabsEmpty,
    required this.activeBucketKey,
    required this.uuid,
    this.onSessionTabOpened,
  });

  final SessionLaunchHost host;
  final ChatTabStore tabStore;
  final ChatState Function() state;
  final SessionLaunchWorkspaceIndex Function() workspaceIndex;
  final Workspace? Function(String workspaceId) workspaceById;
  final SessionTabConnectPrepCallbacks prepCallbacks;
  final bool Function(SessionOpenRequest request) shouldAutoConnect;
  final void Function({
    required int generation,
    required ChatTab tab,
    required AppSession session,
    required TerminalSession shell,
    required SessionOpenRequest request,
    required bool launched,
    required Workspace? workspace,
    required TeamProfile? team,
    required TeamMemberConfig? member,
    VoidCallback? onFinally,
  })
  scheduleShellConnect;
  final void Function({
    required ChatTab tab,
    required String sessionId,
    required SessionOpenRequest request,
    required String message,
  })
  rollbackStagedLaunch;
  final Future<void> Function({
    required ChatTab tab,
    required AppSession session,
    required TeamProfile? team,
    required int generation,
  })
  installTeamRuntimeIfNeeded;
  final ScheduleMemberConnectFn scheduleMemberConnect;
  final void Function() disconnectSession;
  final TerminalSession? Function(TeamProfile team) ensureSession;
  final ChatTab Function(TeamProfile team, {required bool emitChange})
  appendLocalTab;
  final ChatTab Function(TeamProfile team, {required bool emitChange})
  ensureActiveSessionTab;
  final void Function() resetTeamConfigValidationSurface;
  final Future<void> Function(TeamProfile team) scheduleTeamConfigValidation;
  final ChatTab? Function() activeTab;
  final bool Function() autoLaunchAllMembersOnConnect;
  final bool Function() isTabsEmpty;
  final String Function() activeBucketKey;
  final Uuid uuid;

  /// Fired after a new session tab surfaces so the workbench bar can be fed
  /// (the [WorkbenchChatBridge] handshake). Null when the bar is not wired.
  final void Function(
    String workspaceId,
    String sessionId, {
    bool preview,
    bool activate,
  })?
  onSessionTabOpened;
}

/// Composition root for launch pipeline collaborators.
class SessionLaunchBundle {
  SessionLaunchBundle._({
    required this.prepRunner,
    required this.tabSurface,
    required this.materializer,
    required this.pipeline,
    required this.openSession,
  });

  final SessionLaunchConnectPrepRunner prepRunner;
  final SessionTabSurfaceCoordinator tabSurface;
  final SessionDefaultMaterializer materializer;
  final SessionLaunchPipeline pipeline;
  final Future<SessionOpenStatus> Function(SessionOpenRequest request)
  openSession;

  factory SessionLaunchBundle.create(SessionLaunchBundleDeps deps) {
    late final SessionLaunchPipeline pipeline;

    Future<SessionOpenStatus> openSession(SessionOpenRequest request) async {
      final outcome = await pipeline.run(OpenSessionOperation(request));
      return switch (outcome) {
        LaunchOpened(:final status) => status,
        _ => SessionOpenStatus.opened,
      };
    }

    final prepRunner = SessionLaunchConnectPrepRunner(
      host: deps.host,
      prepCallbacks: deps.prepCallbacks,
      shouldAutoConnect: deps.shouldAutoConnect,
      scheduleShellConnect: deps.scheduleShellConnect,
      rollbackStagedLaunch: deps.rollbackStagedLaunch,
      installTeamRuntimeIfNeeded: deps.installTeamRuntimeIfNeeded,
    );

    final tabSurface = SessionTabSurfaceCoordinator(
      host: deps.host,
      tabStore: deps.tabStore,
      workspaceById: deps.workspaceById,
      shouldAutoConnect: deps.shouldAutoConnect,
      prepareNewTabConnect: prepRunner.prepareNewTabConnect,
      prepareExistingTabConnect:
          ({
            required int generation,
            required ChatTab tab,
            required SessionOpenRequest request,
            required bool connect,
          }) => prepRunner.prepareExistingTabConnect(
            generation: generation,
            tab: tab,
            request: request,
            connect: connect,
            workspaceById: deps.workspaceById,
          ),
      prepareDeferredTeamTab: prepRunner.prepareDeferredTeamTab,
      onSessionTabOpened: deps.onSessionTabOpened,
    );

    final materializer = SessionDefaultMaterializer(
      host: deps.host,
      openSession: openSession,
      workspaceIndex: deps.workspaceIndex,
      isTabsEmpty: deps.isTabsEmpty,
      activeBucketKey: deps.activeBucketKey,
    );

    final openRouter = SessionOpenRouter(
      tabStore: deps.tabStore,
      tabSurface: tabSurface,
      workspaceById: deps.workspaceById,
    );

    final memberConnect = MemberConnectStage(
      host: deps.host,
      tabStore: deps.tabStore,
      state: deps.state,
      materializer: materializer,
      openRouter: openRouter,
      scheduleMemberConnect: deps.scheduleMemberConnect,
      disconnectSession: deps.disconnectSession,
      ensureSession: deps.ensureSession,
      appendLocalTab: deps.appendLocalTab,
      ensureActiveSessionTab: deps.ensureActiveSessionTab,
      resetTeamConfigValidationSurface: deps.resetTeamConfigValidationSurface,
      scheduleTeamConfigValidation: deps.scheduleTeamConfigValidation,
      activeTab: deps.activeTab,
      autoLaunchAllMembersOnConnect: deps.autoLaunchAllMembersOnConnect,
      workspaceById: deps.workspaceById,
    );

    pipeline = SessionLaunchPipeline(
      host: deps.host,
      tabStore: deps.tabStore,
      state: deps.state,
      workspaceIndex: deps.workspaceIndex,
      tabSurface: tabSurface,
      openRouter: openRouter,
      memberConnect: memberConnect,
      uuid: deps.uuid,
    );

    return SessionLaunchBundle._(
      prepRunner: prepRunner,
      tabSurface: tabSurface,
      materializer: materializer,
      pipeline: pipeline,
      openSession: openSession,
    );
  }
}
