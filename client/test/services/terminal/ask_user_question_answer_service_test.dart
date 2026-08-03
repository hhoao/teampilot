import 'package:flutter_alacritty/flutter_alacritty.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/agent_status/ask_user_answer_pending_store.dart';
import 'package:teampilot/services/cli/registry/capabilities/ask_user_question_capability.dart';
import 'package:teampilot/services/cli/registry/cli_capability.dart';
import 'package:teampilot/services/cli/registry/cli_tool_definition.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/team/terminal_activity_tracker.dart';
import 'package:teampilot/services/terminal/ask_user_question_answer_service.dart';
import 'package:teampilot/services/terminal/terminal_launch_controller.dart';
import 'package:teampilot/services/terminal/terminal_session.dart';

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
  _StubTool({required this.id, required this.askCap});

  @override
  final CliTool id;

  final AskUserQuestionCapability askCap;

  @override
  Iterable<CliCapability> get capabilities => [askCap];

  @override
  bool get isLaunchSupported => false;
}

CliToolRegistry _registryWith(AskUserQuestionCapability cap, {CliTool cli = CliTool.claude}) {
  final registry = CliToolRegistry();
  registry.register(_StubTool(id: cli, askCap: cap));
  return registry;
}

void main() {
  test('ptyPicker answer writes selection digit, waits, then Enter', () async {
    final writes = <String>[];
    final gaps = <Duration>[];
    final service = AskUserQuestionAnswerService(
      writePty: (_, text) => writes.add(text),
      delay: (d) async => gaps.add(d),
      registry: _registryWith(const PtyAskUserQuestionCapability()),
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

  test('ptyPicker disconnected returns failed', () async {
    final writes = <String>[];
    final service = AskUserQuestionAnswerService(
      writePty: (_, text) => writes.add(text),
      delay: (d) async {},
      registry: _registryWith(const PtyAskUserQuestionCapability()),
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
    expect((disconnected as AskUserAnswerFailed).reason, 'terminal_disconnected');
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
      registry: _registryWith(const PtyAskUserQuestionCapability()),
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
        const OpenCodeAskUserQuestionCapability(),
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
        const OpenCodeAskUserQuestionCapability(),
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
        const OpenCodeAskUserQuestionCapability(),
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

  test('none capability returns failed', () async {
    final service = AskUserQuestionAnswerService(
      registry: _registryWith(
        const NoAskUserQuestionCapability(),
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
