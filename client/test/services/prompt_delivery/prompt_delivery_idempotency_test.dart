import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/agent_runtime/runtime_event.dart';
import 'package:teampilot/services/prompt_delivery/prompt_delivery.dart';
import 'package:teampilot/services/prompt_delivery/prompt_delivery_coordinator.dart';
import 'package:teampilot/services/prompt_delivery/prompt_delivery_store.dart';

class _RecordingCommands implements PromptDeliveryCommands {
  int submitCount = 0;
  int stageCount = 0;

  @override
  Future<void> stage(
    PromptDelivery delivery, {
    required bool Function() canExecute,
  }) async {
    stageCount++;
  }

  @override
  Future<PromptSubmissionResult> submit(
    PromptDelivery delivery, {
    required bool Function() canExecute,
    bool Function()? isAcked,
  }) async {
    submitCount++;
    return PromptSubmissionResult.submitted;
  }
}

void main() {
  const seat = RuntimeSeatKey(sessionId: 'session', memberId: 'member');

  late MemoryPromptDeliveryStore store;
  late _RecordingCommands commands;
  late PromptDeliveryCoordinator coordinator;

  setUp(() {
    store = MemoryPromptDeliveryStore();
    commands = _RecordingCommands();
    coordinator = PromptDeliveryCoordinator(store: store, commands: commands);
  });

  PromptDeliveryRequest request({required String text, String? deliveryId}) =>
      PromptDeliveryRequest(
        seat: seat,
        cli: CliTool.codex,
        text: text,
        deliveryId: deliveryId,
      );

  test(
    'explicit delivery id returns the same record and never resubmits',
    () async {
      final first = await coordinator.submit(
        request(text: 'exact\nrequest', deliveryId: 'teamgen-wf-0'),
      );
      await coordinator.stage(first.id);
      await coordinator.issueSubmit(first.id);
      final submitsAfterFirst = commands.submitCount;

      final restored = await coordinator.submit(
        request(text: 'exact\nrequest', deliveryId: 'teamgen-wf-0'),
      );

      expect(restored.id, first.id);
      expect(restored.state, PromptDeliveryState.submitIssued);
      final stored = await store.forSeat(seat);
      expect(stored, hasLength(1));
      expect(stored.single.id, first.id);
      expect(stored.single.state, PromptDeliveryState.submitIssued);
      expect(commands.submitCount, 1);
      expect(commands.submitCount, submitsAfterFirst);
    },
  );

  test('explicit delivery id rejects a mismatched seat or text', () async {
    await coordinator.submit(request(text: 'one', deliveryId: 'fixed'));
    expect(
      () => coordinator.submit(request(text: 'two', deliveryId: 'fixed')),
      throwsA(isA<StateError>()),
    );
  });

  test('implicit ids retain generated behavior', () async {
    final a = await coordinator.submit(request(text: 'one'));
    final b = await coordinator.submit(request(text: 'one'));
    expect(a.id, isNot(b.id));
  });
}
