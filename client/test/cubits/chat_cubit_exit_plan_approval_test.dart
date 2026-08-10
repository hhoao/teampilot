import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/agent_attention_cubit.dart';
import 'package:teampilot/cubits/chat/model/chat_tab.dart';
import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:teampilot/services/agent_status/agent_attention_state.dart';
import 'package:teampilot/services/agent_status/agent_status_event.dart';
import 'package:teampilot/services/agent_status/exit_plan_mode_hook_gate.dart';
import 'package:teampilot/services/terminal/exit_plan_mode_approval_service.dart';

import '../support/post_frame_test_harness.dart';

void main() {
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  group('ChatCubit exit-plan approve/reject', () {
    late AgentAttentionCubit attention;
    late ExitPlanModeHookGate gate;

    setUp(() {
      attention = AgentAttentionCubit(pruneInterval: null);
      gate = ExitPlanModeHookGate();
    });

    tearDown(() async {
      await attention.close();
    });

    ChatCubit _buildCubit() {
      return ChatCubit(
        executableResolver: () => '/bin/true',
        automationRepository: testAutomationRepository(),
        agentAttentionCubit: attention,
        exitPlanApprovalService: ExitPlanModeApprovalService(hookGate: gate),
      );
    }

    void _seedWaitingTab(ChatCubit cubit, {required String sessionId}) {
      final tab = ChatTab(
        info: ChatTabInfo(id: sessionId, title: sessionId, subtitle: ''),
        cliTeamName: sessionId,
        selectedMemberId: sessionId,
      );
      cubit.tabStore.registerSession(tab);
      cubit.refreshActiveWorkspaceTabs();
      attention.applyEvent(
        sessionId: sessionId,
        memberId: sessionId,
        event: AgentStatusEvent(
          state: AgentSeatAttention.waiting,
          toolName: 'ExitPlanMode',
          toolUseId: 'toolu-plan-1',
          planText: '1. Do x.',
        ),
        skipPermissions: false,
      );
    }

    test('approve completes gate and dismisses waiting', () async {
      final held = gate.wait(
        sessionId: 'sess-ep',
        memberId: 'sess-ep',
        toolUseId: 'toolu-plan-1',
        timeout: const Duration(hours: 1),
      );
      final cubit = _buildCubit();
      addTearDown(cubit.close);
      const sessionId = 'sess-ep';
      _seedWaitingTab(cubit, sessionId: sessionId);

      final result = await cubit.approveExitPlanMode(
        sessionId: sessionId,
        memberId: sessionId,
        toolUseId: 'toolu-plan-1',
      );

      expect(result, isA<ExitPlanApprovalOk>());
      expect((await held)?.deny, isFalse);
      final entry = attention.state.entryFor(
        sessionId: sessionId,
        memberId: sessionId,
      );
      expect(entry?.attention, AgentSeatAttention.working);
    });

    test('reject completes gate with deny and dismisses waiting', () async {
      final held = gate.wait(
        sessionId: 'sess-ep2',
        memberId: 'sess-ep2',
        toolUseId: 'toolu-plan-2',
        timeout: const Duration(hours: 1),
      );
      final cubit = _buildCubit();
      addTearDown(cubit.close);
      const sessionId = 'sess-ep2';
      _seedWaitingTab(cubit, sessionId: sessionId);

      final result = await cubit.rejectExitPlanMode(
        sessionId: sessionId,
        memberId: sessionId,
        toolUseId: 'toolu-plan-2',
      );

      expect(result, isA<ExitPlanApprovalOk>());
      expect((await held)?.deny, isTrue);
      final entry = attention.state.entryFor(
        sessionId: sessionId,
        memberId: sessionId,
      );
      expect(entry?.attention, AgentSeatAttention.working);
    });

    test('failed approval does not dismiss waiting', () async {
      final cubit = _buildCubit();
      addTearDown(cubit.close);
      const sessionId = 'sess-ep3';
      _seedWaitingTab(cubit, sessionId: sessionId);

      final result = await cubit.approveExitPlanMode(
        sessionId: sessionId,
        memberId: sessionId,
        toolUseId: 'no-such-tool-use',
      );

      expect(result, isA<ExitPlanApprovalFailed>());
      final entry = attention.state.entryFor(
        sessionId: sessionId,
        memberId: sessionId,
      );
      expect(entry?.attention, AgentSeatAttention.waiting);
    });
  });
}
