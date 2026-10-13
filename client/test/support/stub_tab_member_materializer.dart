import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/chat/launch/connect/chat_session_shell_factory.dart';
import 'package:teampilot/services/chat/launch/connect/member_connector.dart';
import 'package:teampilot/services/chat/launch/session/tab_member_materializer.dart';
import 'package:teampilot/services/chat/runtime/tab_session_runtime_coordinator.dart';
import 'package:teampilot/services/chat/session/chat_tab_store.dart';

class _NoopMemberConnector implements MemberConnector {
  @override
  void scheduleMemberConnect(
    TeamProfile team,
    TeamMemberConfig member,
    String sessionId, {
    bool selectMember = true,
  }) {}
}

/// Launch-service test hosts that now call [TabMemberMaterializer.markMemberReady]
/// from mixed ACP attach.
TabMemberMaterializer stubTabMemberMaterializer(ChatTabStore tabStore) {
  return TabMemberMaterializer(
    runtime: TabSessionRuntimeCoordinator(
      tabStore: tabStore,
      shellFactory: ChatSessionShellFactory(executableResolver: () => 'true'),
      globalPresets: () => const [],
      activeTeam: () => null,
      isClosed: () => false,
    ),
    tabStore: tabStore,
    connector: _NoopMemberConnector(),
    activeTeam: () => null,
    isClosed: () => false,
    isMixedBusRegistered: (_) => true,
    isMemberConnectOwnedElsewhere: (_, __) => false,
  );
}
