import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/chat/chat_session_shell_factory.dart';
import 'package:teampilot/cubits/chat/chat_tab_store.dart';
import 'package:teampilot/cubits/chat/tab_member_coordination_factory.dart';
import 'package:teampilot/cubits/chat/tab_member_pty_delivery.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/agent_runtime/runtime_event.dart';
import 'package:teampilot/services/prompt_delivery/prompt_delivery.dart';
import 'package:teampilot/services/prompt_delivery/prompt_delivery_coordinator.dart';
import 'package:teampilot/services/prompt_delivery/prompt_delivery_store.dart';

void main() {
  test('one landing send with delayed Codex confirmation has one submit', () async {
    final harness = _DeliveryHarness();

    final id = await harness.delivery.deliverUserCommandToMember(
      's',
      'm',
      'inspect this',
      directToPty: true,
    );
    await harness.publishCodexPromptSubmitted('inspect this');
    await harness.flushQueuedAutomation();

    expect(id, isNotEmpty);
    expect(harness.pty.submittedPrompts, ['inspect this']);
  });
}

final class _DeliveryHarness {
  factory _DeliveryHarness() {
    final pty = _RecordingPromptCommands();
    final coordinator = PromptDeliveryCoordinator(
      store: MemoryPromptDeliveryStore(),
      commands: pty,
    );
    final tabStore = ChatTabStore();
    final delivery = TabMemberPtyDelivery(
      tabStore: tabStore,
      shellFactory: ChatSessionShellFactory(executableResolver: () => 'unused'),
      globalPresets: () => const [],
      activeTeam: () => null,
      isClosed: () => false,
      coordinationFactory: TabMemberCoordinationFactory(
        tabStore: tabStore,
        globalPresets: () => const [],
        activeTeam: () => null,
      ),
      promptDeliveries: coordinator,
    );
    return _DeliveryHarness._(coordinator, pty, delivery);
  }

  _DeliveryHarness._(this.coordinator, this.pty, this.delivery);

  final _RecordingPromptCommands pty;
  final PromptDeliveryCoordinator coordinator;
  final TabMemberPtyDelivery delivery;

  Future<void> publishCodexPromptSubmitted(String prompt) =>
      coordinator.onRuntimeEvent(
        RuntimeEventEnvelope(
          seat: const RuntimeSeatKey(sessionId: 's', memberId: 'm'),
          cli: CliTool.codex,
          kind: RuntimeEventKind.promptSubmitted,
          occurredAt: DateTime.utc(2026, 8, 25),
          prompt: prompt,
          sequence: 1,
        ),
      );

  Future<void> flushQueuedAutomation() => Future<void>.delayed(Duration.zero);
}

final class _RecordingPromptCommands implements PromptDeliveryCommands {
  final List<String> submittedPrompts = [];

  @override
  Future<void> stage(
    PromptDelivery delivery, {
    required bool Function() canExecute,
  }) async {}

  @override
  Future<void> submit(
    PromptDelivery delivery, {
    required bool Function() canExecute,
  }) async {
    if (canExecute()) submittedPrompts.add(delivery.text);
  }
}
