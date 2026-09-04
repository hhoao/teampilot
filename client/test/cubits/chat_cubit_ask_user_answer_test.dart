import 'package:flutter_alacritty/flutter_alacritty.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/agent_attention_cubit.dart';
import 'package:teampilot/cubits/chat/model/chat_tab.dart';
import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:teampilot/services/agent_status/agent_attention_state.dart';
import 'package:teampilot/services/agent_status/agent_permission_request.dart';
import 'package:teampilot/services/agent_status/agent_status_event.dart';
import 'package:teampilot/services/agent_status/ask_user_answer_pending_store.dart';
import 'package:teampilot/services/cli/claude/capabilities/chat_interaction.dart';
import 'package:teampilot/services/cli/opencode/capabilities/chat_interaction.dart';
import 'package:teampilot/services/cli/registry/capabilities/chat_interaction_capability.dart';
import 'package:teampilot/services/cli/registry/cli_capability.dart';
import 'package:teampilot/services/cli/registry/cli_tool_definition.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/team/terminal_activity_tracker.dart';
import 'package:teampilot/services/terminal/ask_user_question_answer_service.dart';
import 'package:teampilot/services/terminal/terminal_launch_controller.dart';
import 'package:teampilot/services/terminal/terminal_session.dart';

import '../support/post_frame_test_harness.dart';
import '../support/rust_lib_test_init.dart';

class _FakeShell extends TerminalSession {
  _FakeShell({required this.connected})
    : super(
        executable: 'unused',
        validateLaunch: false,
        parseExecutable: false,
        launchController: TerminalLaunchController(
          engine: TerminalEngine(config: TerminalConfig.defaults()),
          activityTracker: TerminalActivityTracker(),
          defaultExecutable: 'unused',
          startupDeadline: const Duration(seconds: 5),
          confirmFallback: const Duration(milliseconds: 50),
          validateLaunch: false,
        ),
      );

  final bool connected;

  @override
  bool get isConnected => connected;
}

class _StubTool implements CliToolDefinition {
  _StubTool({required this.id, required this.chatCap});

  @override
  final CliTool id;

  final ChatInteractionCapability chatCap;

  @override
  Iterable<CliCapability> get capabilities => [chatCap];

  @override
  bool get isLaunchSupported => false;
}

CliToolRegistry _ptyRegistry() {
  final registry = CliToolRegistry();
  registry.register(
    _StubTool(id: CliTool.claude, chatCap: const ClaudeChatInteraction()),
  );
  return registry;
}

CliToolRegistry _opencodeRegistry() {
  final registry = CliToolRegistry();
  registry.register(
    _StubTool(id: CliTool.opencode, chatCap: const OpencodeChatInteraction()),
  );
  return registry;
}

void main() {
  setUpAll(initRustLibForTests);
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  group('ChatCubit ask-user answer optimistic dismiss', () {
    late AgentAttentionCubit attention;
    late AskUserAnswerPendingStore store;

    setUp(() {
      attention = AgentAttentionCubit(pruneInterval: null);
      store = AskUserAnswerPendingStore();
    });

    tearDown(() async {
      await attention.close();
    });

    ChatCubit _buildCubit({
      required AskUserQuestionAnswerService answerService,
    }) {
      return ChatCubit(
        executableResolver: () => '/bin/true',
        automationRepository: testAutomationRepository(),
        agentAttentionCubit: attention,
        askUserAnswerPendingStore: store,
        askUserQuestionAnswerService: answerService,
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
        event: const AgentStatusEvent(
          state: AgentSeatAttention.waiting,
          askRequestId: 'ask-req-1',
          toolName: 'AskUserQuestion',
        ),
        skipPermissions: false,
      );
    }

    test('AskUserAnswerOk marks attention answered', () async {
      final writes = <String>[];
      final answerService = AskUserQuestionAnswerService(
        writePty: (_, text) => writes.add(text),
        delay: (_) async {},
        registry: _ptyRegistry(),
        store: store,
      );
      final cubit = _buildCubit(answerService: answerService);
      addTearDown(cubit.close);

      const sessionId = 'sess-ok';
      _seedWaitingTab(cubit, sessionId: sessionId);
      cubit.tabStore.openTabBySessionId(sessionId)!.memberShells[sessionId] =
          _FakeShell(connected: true);

      final result = await cubit.answerAskUserQuestion(
        sessionId: sessionId,
        memberId: sessionId,
        optionIndex: 0,
      );

      expect(result, isA<AskUserAnswerOk>());
      final entry = attention.state.entryFor(
        sessionId: sessionId,
        memberId: sessionId,
      );
      expect(entry?.attention, AgentSeatAttention.working);
      expect(entry?.dismissedAskRequestId, 'ask-req-1');
      expect(writes, ['1', '\r']);
    });

    test('AskUserAnswerFailed does not mark answered', () async {
      final writes = <String>[];
      final answerService = AskUserQuestionAnswerService(
        writePty: (_, text) => writes.add(text),
        delay: (_) async {},
        registry: _ptyRegistry(),
        store: store,
      );
      final cubit = _buildCubit(answerService: answerService);
      addTearDown(cubit.close);

      const sessionId = 'sess-fail';
      _seedWaitingTab(cubit, sessionId: sessionId);
      // No shell → facade returns terminal_disconnected.

      final result = await cubit.answerAskUserQuestion(
        sessionId: sessionId,
        memberId: sessionId,
        optionIndex: 0,
      );

      expect(result, isA<AskUserAnswerFailed>());
      expect((result as AskUserAnswerFailed).reason, 'terminal_disconnected');
      final entry = attention.state.entryFor(
        sessionId: sessionId,
        memberId: sessionId,
      );
      expect(entry?.attention, AgentSeatAttention.waiting);
      expect(entry?.dismissedAskRequestId, isNull);
      expect(writes, isEmpty);
    });

    test('cancel AskUserAnswerOk also marks answered', () async {
      final writes = <String>[];
      final answerService = AskUserQuestionAnswerService(
        writePty: (_, text) => writes.add(text),
        delay: (_) async {},
        registry: _ptyRegistry(),
        store: store,
      );
      final cubit = _buildCubit(answerService: answerService);
      addTearDown(cubit.close);

      const sessionId = 'sess-cancel';
      _seedWaitingTab(cubit, sessionId: sessionId);
      cubit.tabStore.openTabBySessionId(sessionId)!.memberShells[sessionId] =
          _FakeShell(connected: true);

      final result = await cubit.cancelAskUserQuestion(
        sessionId: sessionId,
        memberId: sessionId,
      );

      expect(result, isA<AskUserAnswerOk>());
      final entry = attention.state.entryFor(
        sessionId: sessionId,
        memberId: sessionId,
      );
      expect(entry?.attention, AgentSeatAttention.working);
      expect(entry?.dismissedAskRequestId, 'ask-req-1');
      expect(writes, ['\x1b']);
    });
  });

  group('ChatCubit permission reply', () {
    late AgentAttentionCubit attention;
    late AskUserAnswerPendingStore store;

    setUp(() {
      attention = AgentAttentionCubit(pruneInterval: null);
      store = AskUserAnswerPendingStore();
    });

    tearDown(() async {
      await attention.close();
    });

    ChatCubit _buildCubit({
      required AskUserQuestionAnswerService answerService,
    }) {
      return ChatCubit(
        executableResolver: () => '/bin/true',
        automationRepository: testAutomationRepository(),
        agentAttentionCubit: attention,
        askUserAnswerPendingStore: store,
        askUserQuestionAnswerService: answerService,
      );
    }

    void _seedWaitingPermissionTab(
      ChatCubit cubit, {
      required String sessionId,
    }) {
      final tab =
          ChatTab(
              info: ChatTabInfo(id: sessionId, title: sessionId, subtitle: ''),
              cliTeamName: sessionId,
              selectedMemberId: sessionId,
              workspaceId: 'workspace-1',
            )
            ..persistedSession = AppSession(
              sessionId: sessionId,
              workspaceId: 'workspace-1',
              cli: CliTool.opencode,
              createdAt: 0,
            );
      cubit.tabStore.registerSession(tab);
      cubit.refreshActiveWorkspaceTabs();
      attention.applyEvent(
        sessionId: sessionId,
        memberId: sessionId,
        event: const AgentStatusEvent(
          state: AgentSeatAttention.waiting,
          hookEventName: 'permission.asked',
          askRequestId: 'perm-1',
          permissionRequest: AgentPermissionRequest(
            id: 'perm-1',
            description: 'Run `npm install`',
          ),
        ),
        skipPermissions: false,
      );
    }

    test(
      'answerPermissionRequest ok stores reply and marks answered',
      () async {
        final answerService = AskUserQuestionAnswerService(
          registry: _opencodeRegistry(),
          store: store,
        );
        final cubit = _buildCubit(answerService: answerService);
        addTearDown(cubit.close);

        const sessionId = 'sess-perm';
        _seedWaitingPermissionTab(cubit, sessionId: sessionId);

        final result = await cubit.answerPermissionRequest(
          sessionId: sessionId,
          memberId: sessionId,
          kind: AgentPermissionReplyKind.always,
        );

        expect(result, isA<AskUserAnswerOk>());
        final taken = store.take(
          sessionId: sessionId,
          memberId: sessionId,
          requestId: 'perm-1',
        );
        expect(taken, isNotNull);
        expect(taken!.permissionReply, 'always');
        final entry = attention.state.entryFor(
          sessionId: sessionId,
          memberId: sessionId,
        );
        expect(entry?.attention, AgentSeatAttention.working);
        expect(entry?.dismissedAskRequestId, 'perm-1');
      },
    );

    test('answerPermissionRequest failed does not mark answered', () async {
      // Claude registry → pluginSdkReply capability absent → unsupported.
      final answerService = AskUserQuestionAnswerService(
        registry: _ptyRegistry(),
        store: store,
      );
      final cubit = _buildCubit(answerService: answerService);
      addTearDown(cubit.close);

      const sessionId = 'sess-perm-fail';
      _seedWaitingPermissionTab(cubit, sessionId: sessionId);

      final result = await cubit.answerPermissionRequest(
        sessionId: sessionId,
        memberId: sessionId,
        kind: AgentPermissionReplyKind.allowOnce,
      );

      expect(result, isA<AskUserAnswerFailed>());
      expect((result as AskUserAnswerFailed).reason, 'unsupported');
      final entry = attention.state.entryFor(
        sessionId: sessionId,
        memberId: sessionId,
      );
      expect(entry?.attention, AgentSeatAttention.waiting);
      expect(entry?.dismissedAskRequestId, isNull);
      expect(
        store.take(
          sessionId: sessionId,
          memberId: sessionId,
          requestId: 'perm-1',
        ),
        isNull,
      );
    });
  });
}
