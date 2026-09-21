import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/agent_runtime/runtime_event.dart';

import '../support/post_frame_test_harness.dart';

void main() {
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  test('ChatCubit journals UserPromptSubmit without AppShell wiring', () async {
    final cubit = ChatCubit(
      executableResolver: () => 'claude',
      storage: testHomeStorage,
      automationRepository: testAutomationRepository(),
    );
    addTearDown(cubit.close);

    // First session-runtime touch is when AppShell's lazy coordinator
    // getter would resolve; a cubit constructed by tests (or any
    // non-shell host) must still own the same hook → delivery join.
    cubit.sessionRuntime;

    final runtime = cubit.lifecycle.agentRuntime;
    expect(
      runtime,
      isNotNull,
      reason:
          'UserPromptSubmit confirms PromptDeliveryCoordinator only '
          'through AgentRuntime; ChatCubit must bind it without AppShell.',
    );

    cubit.agentStatusSeatLookup!.registerSeat(
      sessionId: 'session',
      memberId: 'lead',
      cli: CliTool.claude,
      skipPermissions: false,
    );

    const seat = RuntimeSeatKey(sessionId: 'session', memberId: 'lead');
    final envelope = await runtime!.gateway.handleJson(seat, {
      'hook_event_name': 'UserPromptSubmit',
      'prompt': 'hello from operator',
    });

    expect(envelope, isNotNull);
    expect(envelope!.kind, RuntimeEventKind.promptSubmitted);
    expect(envelope.prompt, 'hello from operator');
  });
}
