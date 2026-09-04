import 'package:flutter_alacritty/flutter_alacritty.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/agent_status/agent_permission_request.dart';
import 'package:teampilot/services/agent_status/ask_user_answer_pending_store.dart';
import 'package:teampilot/services/agent_status/general_permission_request_gate.dart';
import 'package:teampilot/services/cli/claude/capabilities/chat_interaction.dart';
import 'package:teampilot/services/cli/cursor/capabilities/chat_interaction.dart';
import 'package:teampilot/services/cli/opencode/capabilities/chat_interaction.dart';
import 'package:teampilot/services/cli/registry/capabilities/chat_interaction_capability.dart';
import 'package:teampilot/services/cli/registry/cli_capability.dart';
import 'package:teampilot/services/cli/registry/cli_tool_definition.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/team/terminal_activity_tracker.dart';
import 'package:teampilot/services/terminal/ask_user_question_answer_service.dart';
import 'package:teampilot/services/terminal/terminal_launch_controller.dart';
import 'package:teampilot/services/terminal/terminal_session.dart';
import '../../support/rust_lib_test_init.dart';

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

CliToolRegistry _registryWith(
  ChatInteractionCapability cap, {
  CliTool cli = CliTool.claude,
}) {
  final registry = CliToolRegistry();
  registry.register(_StubTool(id: cli, chatCap: cap));
  return registry;
}

void main() {
  setUpAll(initRustLibForTests);
  test('ptyPicker answer writes selection digit, waits, then Enter', () async {
    final writes = <String>[];
    final gaps = <Duration>[];
    final service = AskUserQuestionAnswerService(
      writePty: (_, text) => writes.add(text),
      delay: (d) async => gaps.add(d),
      registry: _registryWith(const ClaudeChatInteraction()),
      store: AskUserAnswerPendingStore(),
    );
    final result = await service.answer(
      cli: CliTool.claude,
      sessionId: 'sess',
      memberId: 'member',
      shell: _FakeShell(connected: true),
      askRequestId: null,
      optionIndex: 1,
    );

    expect(result, isA<AskUserAnswerOk>());
    // Option index 1 → picker digit "2"; trailing Enter after the settle gap.
    expect(writes, ['2', '\r']);
    expect(gaps, [AskUserQuestionAnswerService.selectionToSubmitGap]);
  });

  test('ptyPicker freeText writes Other digit, text, then Enter', () async {
    final writes = <String>[];
    final gaps = <Duration>[];
    final service = AskUserQuestionAnswerService(
      writePty: (_, text) => writes.add(text),
      delay: (d) async => gaps.add(d),
      registry: _registryWith(const ClaudeChatInteraction()),
      store: AskUserAnswerPendingStore(),
    );
    final result = await service.answer(
      cli: CliTool.claude,
      sessionId: 'sess',
      memberId: 'member',
      shell: _FakeShell(connected: true),
      askRequestId: null,
      optionIndex: 3,
      freeText: '两杯半',
    );

    expect(result, isA<AskUserAnswerOk>());
    expect(writes, ['4', '两杯半', '\r']);
    expect(gaps, [
      AskUserQuestionAnswerService.selectionToSubmitGap,
      AskUserQuestionAnswerService.selectionToSubmitGap,
    ]);
  });

  test('ptyPicker multi-question walks Right then digits then Enter', () async {
    final writes = <String>[];
    final service = AskUserQuestionAnswerService(
      writePty: (_, text) => writes.add(text),
      delay: (d) async {},
      registry: _registryWith(const ClaudeChatInteraction()),
      store: AskUserAnswerPendingStore(),
    );
    final result = await service.answer(
      cli: CliTool.claude,
      sessionId: 'sess',
      memberId: 'member',
      shell: _FakeShell(connected: true),
      askRequestId: null,
      optionIndices: const [0, 2, 1],
    );

    expect(result, isA<AskUserAnswerOk>());
    expect(writes, [
      '1',
      AskUserQuestionAnswerService.nextQuestionKey,
      '3',
      AskUserQuestionAnswerService.nextQuestionKey,
      '2',
      '\r',
    ]);
  });

  test('ptyPicker disconnected returns failed', () async {
    final writes = <String>[];
    final service = AskUserQuestionAnswerService(
      writePty: (_, text) => writes.add(text),
      delay: (d) async {},
      registry: _registryWith(const ClaudeChatInteraction()),
      store: AskUserAnswerPendingStore(),
    );
    final disconnected = await service.answer(
      cli: CliTool.claude,
      sessionId: 'sess',
      memberId: 'member',
      shell: _FakeShell(connected: false),
      askRequestId: null,
      optionIndex: 1,
    );
    expect(disconnected, isA<AskUserAnswerFailed>());
    expect(
      (disconnected as AskUserAnswerFailed).reason,
      'terminal_disconnected',
    );
    expect(writes, isEmpty);

    final nullShell = await service.answer(
      cli: CliTool.claude,
      sessionId: 'sess',
      memberId: 'member',
      shell: null,
      askRequestId: null,
      optionIndex: 1,
    );
    expect(nullShell, isA<AskUserAnswerFailed>());
    expect((nullShell as AskUserAnswerFailed).reason, 'terminal_disconnected');
  });

  test('ptyPicker cancel writes Esc', () async {
    final writes = <String>[];
    final service = AskUserQuestionAnswerService(
      writePty: (_, text) => writes.add(text),
      registry: _registryWith(const ClaudeChatInteraction()),
      store: AskUserAnswerPendingStore(),
    );
    final result = await service.cancel(
      cli: CliTool.claude,
      sessionId: 'sess',
      memberId: 'member',
      shell: _FakeShell(connected: true),
      askRequestId: null,
    );
    expect(result, isA<AskUserAnswerOk>());
    expect(writes, ['\x1b']);
  });

  test('pluginSdkReply puts pending answers and returns ok', () async {
    final store = AskUserAnswerPendingStore();
    final service = AskUserQuestionAnswerService(
      registry: _registryWith(
        const OpencodeChatInteraction(),
        cli: CliTool.opencode,
      ),
      store: store,
    );
    final answers = [
      ['yes'],
      ['option-a', 'option-b'],
    ];
    final result = await service.answer(
      cli: CliTool.opencode,
      sessionId: 'sess-a',
      memberId: 'member-1',
      shell: null,
      askRequestId: 'req-1',
      answers: answers,
    );

    expect(result, isA<AskUserAnswerOk>());
    final taken = store.take(
      sessionId: 'sess-a',
      memberId: 'member-1',
      requestId: 'req-1',
    );
    expect(taken, isNotNull);
    expect(taken!.requestId, 'req-1');
    expect(taken.answers, answers);
    expect(taken.reject, isFalse);
  });

  test('pluginSdkReply cancel puts reject', () async {
    final store = AskUserAnswerPendingStore();
    final service = AskUserQuestionAnswerService(
      registry: _registryWith(
        const OpencodeChatInteraction(),
        cli: CliTool.opencode,
      ),
      store: store,
    );
    final result = await service.cancel(
      cli: CliTool.opencode,
      sessionId: 'sess-a',
      memberId: 'member-1',
      shell: null,
      askRequestId: 'req-reject',
    );

    expect(result, isA<AskUserAnswerOk>());
    final taken = store.take(
      sessionId: 'sess-a',
      memberId: 'member-1',
      requestId: 'req-reject',
    );
    expect(taken, isNotNull);
    expect(taken!.requestId, 'req-reject');
    expect(taken.reject, isTrue);
    expect(taken.answers, isNull);
  });

  test('pluginSdkReply missing requestId returns failed', () async {
    final store = AskUserAnswerPendingStore();
    final service = AskUserQuestionAnswerService(
      registry: _registryWith(
        const OpencodeChatInteraction(),
        cli: CliTool.opencode,
      ),
      store: store,
    );
    final result = await service.answer(
      cli: CliTool.opencode,
      sessionId: 'sess-a',
      memberId: 'member-1',
      shell: null,
      askRequestId: null,
      answers: [
        ['yes'],
      ],
    );

    expect(result, isA<AskUserAnswerFailed>());
    expect((result as AskUserAnswerFailed).reason, 'missing_request_id');
  });

  test('answerPermission puts permission reply entry for opencode', () async {
    final store = AskUserAnswerPendingStore();
    final service = AskUserQuestionAnswerService(
      registry: _registryWith(
        const OpencodeChatInteraction(),
        cli: CliTool.opencode,
      ),
      store: store,
    );
    final result = await service.answerPermission(
      cli: CliTool.opencode,
      sessionId: 'sess-a',
      memberId: 'member-1',
      requestId: 'perm-1',
      kind: AgentPermissionReplyKind.always,
    );

    expect(result, isA<AskUserAnswerOk>());
    final taken = store.take(
      sessionId: 'sess-a',
      memberId: 'member-1',
      requestId: 'perm-1',
    );
    expect(taken, isNotNull);
    expect(taken!.requestId, 'perm-1');
    expect(taken.permissionReply, 'always');
    expect(taken.answers, isNull);
    expect(taken.reject, isFalse);
  });

  test('answerPermission missing requestId returns failed', () async {
    final store = AskUserAnswerPendingStore();
    final service = AskUserQuestionAnswerService(
      registry: _registryWith(
        const OpencodeChatInteraction(),
        cli: CliTool.opencode,
      ),
      store: store,
    );
    final result = await service.answerPermission(
      cli: CliTool.opencode,
      sessionId: 'sess-a',
      memberId: 'member-1',
      requestId: null,
      kind: AgentPermissionReplyKind.allowOnce,
    );

    expect(result, isA<AskUserAnswerFailed>());
    expect((result as AskUserAnswerFailed).reason, 'missing_request_id');
  });

  test('answerPermission unsupported cli without gate returns failed', () async {
    final store = AskUserAnswerPendingStore();
    final service = AskUserQuestionAnswerService(
      registry: _registryWith(
        const ClaudeChatInteraction(),
        cli: CliTool.claude,
      ),
      store: store,
    );
    final result = await service.answerPermission(
      cli: CliTool.claude,
      sessionId: 'sess-a',
      memberId: 'member-1',
      requestId: 'perm-1',
      kind: AgentPermissionReplyKind.allowOnce,
    );

    expect(result, isA<AskUserAnswerFailed>());
    expect((result as AskUserAnswerFailed).reason, 'unsupported');
    expect(
      store.take(
        sessionId: 'sess-a',
        memberId: 'member-1',
        requestId: 'perm-1',
      ),
      isNull,
    );
  });

  test('hook-hold channel completes the gate with an allow reply', () async {
    final gate = GeneralPermissionRequestGate();
    final service = AskUserQuestionAnswerService(generalPermissionGate: gate);
    final held = gate.wait(sessionId: 's', memberId: 'm');
    final result = await service.answerPermission(
      cli: CliTool.claude,
      sessionId: 's',
      memberId: 'm',
      kind: AgentPermissionReplyKind.allowOnce,
    );
    expect(result, isA<AskUserAnswerOk>());
    final reply = await held;
    expect(reply, isNotNull);
    expect(reply!.deny, isFalse);
  });

  test('hook-hold always echoes the suggestion payload', () async {
    final gate = GeneralPermissionRequestGate();
    final service = AskUserQuestionAnswerService(generalPermissionGate: gate);
    final held = gate.wait(sessionId: 's', memberId: 'm');
    await service.answerPermission(
      cli: CliTool.claude,
      sessionId: 's',
      memberId: 'm',
      kind: AgentPermissionReplyKind.always,
      alwaysPayload: {
        'type': 'addRules',
        'rules': [
          {'toolName': 'Bash', 'ruleContent': 'rm -rf node_modules'},
        ],
        'behavior': 'allow',
        'destination': 'localSettings',
      },
    );
    final reply = await held;
    expect(reply!.updatedPermissions, hasLength(1));
  });

  test('hook-hold deny completes the gate with a deny reply', () async {
    final gate = GeneralPermissionRequestGate();
    final service = AskUserQuestionAnswerService(generalPermissionGate: gate);
    final held = gate.wait(sessionId: 's', memberId: 'm');
    final result = await service.answerPermission(
      cli: CliTool.claude,
      sessionId: 's',
      memberId: 'm',
      kind: AgentPermissionReplyKind.reject,
    );
    expect(result, isA<AskUserAnswerOk>());
    final reply = await held;
    expect(reply, isNotNull);
    expect(reply!.deny, isTrue);
    expect(reply.message, isNotNull);
  });

  test('hook-hold without a held waiter returns failed', () async {
    final gate = GeneralPermissionRequestGate();
    final service = AskUserQuestionAnswerService(generalPermissionGate: gate);
    final result = await service.answerPermission(
      cli: CliTool.claude,
      sessionId: 's',
      memberId: 'm',
      kind: AgentPermissionReplyKind.allowOnce,
    );
    expect(result, isA<AskUserAnswerFailed>());
    expect((result as AskUserAnswerFailed).reason, 'no_pending_permission');
  });

  test('releasePermission falls through to the native TUI', () async {
    final gate = GeneralPermissionRequestGate();
    final service = AskUserQuestionAnswerService(generalPermissionGate: gate);
    final held = gate.wait(sessionId: 's', memberId: 'm');
    final result = await service.releasePermission(
      cli: CliTool.claude,
      sessionId: 's',
      memberId: 'm',
    );
    expect(result, isA<AskUserAnswerOk>());
    expect(await held, isNull);
  });

  test('releasePermission without a hold returns failed', () async {
    final gate = GeneralPermissionRequestGate();
    final service = AskUserQuestionAnswerService(generalPermissionGate: gate);
    final result = await service.releasePermission(
      cli: CliTool.claude,
      sessionId: 's',
      memberId: 'm',
    );
    expect(result, isA<AskUserAnswerFailed>());
    expect((result as AskUserAnswerFailed).reason, 'no_pending_permission');
  });

  test('plugin-SDK channel keeps the string reply path', () async {
    final store = AskUserAnswerPendingStore();
    final service = AskUserQuestionAnswerService(store: store);
    final result = await service.answerPermission(
      cli: CliTool.opencode,
      sessionId: 's',
      memberId: 'm',
      requestId: 'perm-1',
      kind: AgentPermissionReplyKind.always,
    );
    expect(result, isA<AskUserAnswerOk>());
    final entry = store.take(sessionId: 's', memberId: 'm', requestId: 'perm-1');
    expect(entry?.permissionReply, 'always');
  });

  test('none capability returns failed', () async {
    final service = AskUserQuestionAnswerService(
      registry: _registryWith(
        const CursorChatInteraction(),
        cli: CliTool.cursor,
      ),
      store: AskUserAnswerPendingStore(),
    );
    final answer = await service.answer(
      cli: CliTool.cursor,
      sessionId: 'sess',
      memberId: 'member',
      shell: _FakeShell(connected: true),
      askRequestId: null,
      optionIndex: 0,
    );
    expect(answer, isA<AskUserAnswerFailed>());
    expect((answer as AskUserAnswerFailed).reason, 'unsupported');

    final cancel = await service.cancel(
      cli: CliTool.cursor,
      sessionId: 'sess',
      memberId: 'member',
      shell: _FakeShell(connected: true),
      askRequestId: null,
    );
    expect(cancel, isA<AskUserAnswerFailed>());
    expect((cancel as AskUserAnswerFailed).reason, 'unsupported');
  });
}
