import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/agent_runtime/runtime_event.dart';
import 'package:teampilot/services/prompt_delivery/prompt_delivery.dart';
import 'package:teampilot/services/prompt_delivery/prompt_delivery_coordinator.dart';
import 'package:teampilot/services/prompt_delivery/prompt_delivery_store.dart';

void main() {
  const seat = RuntimeSeatKey(sessionId: 'session', memberId: 'member');

  late MemoryPromptDeliveryStore store;
  late _FakePromptDeliveryCommands commands;
  late PromptDeliveryCoordinator coordinator;
  late DateTime now;

  setUp(() {
    store = MemoryPromptDeliveryStore();
    commands = _FakePromptDeliveryCommands();
    now = DateTime.utc(2026, 8, 25, 12);
    coordinator = PromptDeliveryCoordinator(
      store: store,
      commands: commands,
      clock: () => now,
    );
  });

  PromptDeliveryRequest request({required String text}) =>
      PromptDeliveryRequest(seat: seat, cli: CliTool.codex, text: text);

  RuntimeEventEnvelope promptSubmitted({required String text}) =>
      RuntimeEventEnvelope(
        seat: seat,
        cli: CliTool.codex,
        kind: RuntimeEventKind.promptSubmitted,
        occurredAt: now,
        prompt: text,
        sequence: 1,
      );

  test('same text confirms only the active seat epoch', () async {
    final first = await coordinator.submit(request(text: 'same'));
    await coordinator.issueSubmit(first.id);
    await coordinator.onRuntimeEvent(promptSubmitted(text: 'same'));
    final second = await coordinator.submit(request(text: 'same'));

    expect((await store.read(first.id))!.state, PromptDeliveryState.confirmed);
    expect((await store.read(second.id))!.state, PromptDeliveryState.created);
  });

  test('permits only one non-terminal delivery for a seat', () async {
    await coordinator.submit(request(text: 'first'));

    await expectLater(
      coordinator.submit(request(text: 'second')),
      throwsA(isA<StateError>()),
    );
  });

  test('does not confirm a delivery before its submit is issued', () async {
    final delivery = await coordinator.submit(request(text: 'same'));

    await coordinator.onRuntimeEvent(promptSubmitted(text: 'same'));

    expect((await store.read(delivery.id))!.state, PromptDeliveryState.created);
  });

  test('old same-text event cannot confirm the next prompt epoch', () async {
    final first = await coordinator.submit(request(text: 'same'));
    await coordinator.issueSubmit(first.id);
    await coordinator.onRuntimeEvent(promptSubmitted(text: 'same'));
    now = now.add(const Duration(seconds: 1));

    final second = await coordinator.submit(request(text: 'same'));
    await coordinator.issueSubmit(second.id);
    // Model delayed gateway ingress: the duplicate reaches the gateway only
    // after epoch two exists, so it receives a fresh gateway timestamp.
    await coordinator.onRuntimeEvent(promptSubmitted(text: 'same'));

    expect(
      (await store.read(second.id))!.state,
      PromptDeliveryState.submitIssued,
    );
  });

  test('recovery retry rejects a delayed same-text weak event', () async {
    final first = await coordinator.submit(request(text: 'same'));
    await coordinator.issueSubmit(first.id);
    await coordinator.restoreSeat(seat);
    now = now.add(const Duration(seconds: 1));
    final restored = PromptDeliveryCoordinator(
      store: store,
      commands: commands,
      clock: () => now,
    );

    final retry = await restored.submit(request(text: 'same'));
    await restored.issueSubmit(retry.id);
    await restored.onRuntimeEvent(promptSubmitted(text: 'same'));

    expect(
      (await store.read(retry.id))!.state,
      PromptDeliveryState.submitIssued,
    );
  });

  test(
    'malformed exact event and another CLI cannot confirm a delivery',
    () async {
      final delivery = await coordinator.submit(request(text: 'same'));
      await coordinator.issueSubmit(delivery.id);
      await coordinator.onRuntimeEvent(
        RuntimeEventEnvelope(
          seat: seat,
          cli: CliTool.codex,
          kind: RuntimeEventKind.promptSubmitted,
          occurredAt: now,
          prompt: 'same',
          correlationStrength: RuntimeCorrelationStrength.exact,
          sequence: 1,
        ),
      );
      await coordinator.onRuntimeEvent(
        RuntimeEventEnvelope(
          seat: seat,
          cli: CliTool.claude,
          kind: RuntimeEventKind.promptSubmitted,
          occurredAt: now,
          prompt: 'same',
          sequence: 2,
        ),
      );

      expect(
        (await store.read(delivery.id))!.state,
        PromptDeliveryState.submitIssued,
      );
    },
  );

  test('command fences permit only their exact live state', () async {
    final delivery = await coordinator.submit(request(text: 'same'));
    await coordinator.stage(delivery.id);
    expect(commands.stageFence.single, isTrue);

    await coordinator.issueSubmit(delivery.id);
    expect(commands.stageFence.single, isFalse);
    expect(commands.submitFence.single, isTrue);
  });

  test(
    'submitIssued restores as submittedUnknown without a new PTY command',
    () async {
      final delivery = PromptDelivery(
        id: 'd1',
        seat: seat,
        cli: CliTool.codex,
        text: 'recover me',
        normalizedText: 'recover me',
        promptEpoch: 1,
        state: PromptDeliveryState.submitIssued,
        createdAt: DateTime.utc(2026, 8, 25),
        updatedAt: DateTime.utc(2026, 8, 25),
      );
      await store.save(delivery);

      final restored = PromptDeliveryCoordinator(
        store: store,
        commands: commands,
      );
      await restored.restoreSeat(seat);

      expect(
        (await store.read('d1'))!.state,
        PromptDeliveryState.submittedUnknown,
      );
      expect(commands.writes, isEmpty);
    },
  );
}

final class _FakePromptDeliveryCommands implements PromptDeliveryCommands {
  final List<String> writes = [];
  final List<bool Function()> _stageFences = [];
  final List<bool Function()> _submitFences = [];

  List<bool> get stageFence => _stageFences.map((fence) => fence()).toList();
  List<bool> get submitFence => _submitFences.map((fence) => fence()).toList();

  @override
  Future<void> stage(
    PromptDelivery delivery, {
    required bool Function() canExecute,
  }) async {
    _stageFences.add(canExecute);
    writes.add('stage:${delivery.id}');
  }

  @override
  Future<PromptSubmissionResult> submit(
    PromptDelivery delivery, {
    required bool Function() canExecute,
  }) async {
    _submitFences.add(canExecute);
    writes.add('submit:${delivery.id}');
    return PromptSubmissionResult.submitted;
  }
}
