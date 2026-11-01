import '../../cubits/session/acp/acp_chat_runtime_cubit.dart';
import '../../models/app_session.dart';
import '../chat/launch/session/tab_member_materializer.dart';
import '../chat/runtime/tab_session_runtime_coordinator.dart';
import '../chat/session/chat_tab.dart';
import '../chat/session/chat_tab_store.dart';
import 'automation_prompt_delivery.dart';

/// Delivery seam for automation dispatch (ACP cubit, TeamBus, or PTY inject).
abstract interface class AutomationBusGateway {
  Future<AutomationDeliveryOutcome> deliverUserCommandToMember(
    AppSession session,
    String memberId,
    String message,
  );

  /// PTY connected and member past startup (TUI frame + agent loop when needed).
  Future<void> ensureMemberReady(String sessionId, String memberId);
}

class TabTeamBusGateway implements AutomationBusGateway {
  TabTeamBusGateway({
    required TabMemberMaterializer memberMaterializer,
    required TabSessionRuntimeCoordinator sessionRuntime,
    required ChatTabStore tabStore,
    Future<void> Function(String sessionId)? activatePersonalAcp,
    Future<void> Function(String sessionId, String memberId)? activateMemberSeat,
    Duration acpActivationTimeout = const Duration(seconds: 30),
  }) : _memberMaterializer = memberMaterializer,
       _sessionRuntime = sessionRuntime,
       _tabStore = tabStore,
       _activatePersonalAcp = activatePersonalAcp,
       _activateMemberSeat = activateMemberSeat,
       _acpActivationTimeout = acpActivationTimeout;

  final TabMemberMaterializer _memberMaterializer;
  final TabSessionRuntimeCoordinator _sessionRuntime;
  final ChatTabStore _tabStore;
  final Future<void> Function(String sessionId)? _activatePersonalAcp;
  final Future<void> Function(String sessionId, String memberId)?
  _activateMemberSeat;
  final Duration _acpActivationTimeout;

  @override
  Future<AutomationDeliveryOutcome> deliverUserCommandToMember(
    AppSession session,
    String memberId,
    String message,
  ) {
    final tab = _tabStore.getOpenTabBySessionId(session.sessionId);
    if (tab == null) {
      return Future.value(
        const AutomationDeliveryOutcome.failed('tab_unavailable'),
      );
    }
    return deliverAutomationPrompt(
      session: session,
      memberId: memberId,
      message: message,
      acpSend: () => acpRuntimeForView(
        session: session,
        tab: tab,
        selectedMemberId: memberId,
      )?.sendPrompt,
      acpReadiness: () => _acpReadiness(session, tab, memberId),
      activateAcp: () => _activate(session, memberId),
      ptySubmit: (sessionId, memberId, text) => _sessionRuntime
          .deliverUserCommandToMember(
            sessionId,
            memberId,
            text,
            directToPty: true,
          ),
      activationTimeout: _acpActivationTimeout,
    );
  }

  Future<void> _activate(AppSession session, String memberId) async {
    if (session.isSimple) {
      await _activatePersonalAcp?.call(session.sessionId);
      return;
    }
    await _activateMemberSeat?.call(session.sessionId, memberId);
  }

  AutomationAcpReadiness _acpReadiness(
    AppSession session,
    ChatTab tab,
    String memberId,
  ) {
    final cubit = acpRuntimeForView(
      session: session,
      tab: tab,
      selectedMemberId: memberId,
    );
    if (cubit == null) return AutomationAcpReadiness.missing;
    return switch (cubit.state.phase) {
      AcpChatPhase.launching => AutomationAcpReadiness.launching,
      AcpChatPhase.ready || AcpChatPhase.idle => AutomationAcpReadiness.ready,
      AcpChatPhase.ended => AutomationAcpReadiness.ended,
    };
  }

  @override
  Future<void> ensureMemberReady(String sessionId, String memberId) {
    return _memberMaterializer.ensureMemberInputReady(
      sessionId,
      memberId,
      directToPty: true,
    );
  }
}
