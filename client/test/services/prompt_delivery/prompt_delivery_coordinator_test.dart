import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/agent_runtime/runtime_event.dart';
import 'package:teampilot/services/prompt_delivery/prompt_delivery.dart';
import 'package:teampilot/services/prompt_delivery/prompt_delivery_coordinator.dart';
import 'package:teampilot/services/prompt_delivery/prompt_delivery_store.dart';
import '../../support/in_memory_filesystem.dart';

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

  test('a later submit recovers an unconfirmed issued delivery', () async {
    final first = await coordinator.submit(request(text: 'first'));
    await coordinator.issueSubmit(first.id);

    final second = await coordinator.submit(request(text: 'second'));

    expect(
      (await store.read(first.id))!.state,
      PromptDeliveryState.submittedUnknown,
    );
    expect(second.state, PromptDeliveryState.created);
    expect((await store.activeFor(seat)).single.id, second.id);
  });

  test('a later submit fails an unissued leftover and claims the seat',
      () async {
    final first = await coordinator.submit(request(text: 'stuck'));

    final second = await coordinator.submit(request(text: 'retry'));

    expect((await store.read(first.id))!.state, PromptDeliveryState.failed);
    expect(second.text, 'retry');
    expect((await store.activeFor(seat)).single.id, second.id);
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

  test('a dropped submit cannot be weakly confirmed afterwards', () async {
    final outcomeCommands = _OutcomePromptDeliveryCommands(
      PromptSubmissionResult.dropped,
    );
    final dropping = PromptDeliveryCoordinator(
      store: store,
      commands: outcomeCommands,
      clock: () => now,
    );

    final delivery = await dropping.submit(request(text: 'same'));
    await dropping.issueSubmit(delivery.id);

    // The fence dropped the CR: the record must leave submitIssued so a later
    // same-text hook can never mis-confirm it.
    expect(
      (await store.read(delivery.id))!.state,
      PromptDeliveryState.submittedUnknown,
    );

    await coordinator.onRuntimeEvent(promptSubmitted(text: 'same'));

    expect(
      (await store.read(delivery.id))!.state,
      PromptDeliveryState.submittedUnknown,
    );
  });

  test(
    'restoreSeat fails a non-issued active delivery and unblocks the seat',
    () async {
      final delivery = PromptDelivery(
        id: 'd1',
        seat: seat,
        cli: CliTool.codex,
        text: 'never issued',
        normalizedText: 'never issued',
        promptEpoch: 1,
        state: PromptDeliveryState.created,
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
        PromptDeliveryState.failed,
      );
      // A seat wedged by an orphaned non-terminal delivery must accept a new
      // submit after restore.
      final next = await restored.submit(request(text: 'recovered'));
      expect(next.id, isNot('d1'));
    },
  );

  test('a failed submit closes its delivery as failed', () async {
    final outcomeCommands = _OutcomePromptDeliveryCommands(
      PromptSubmissionResult.failed,
    );
    final failing = PromptDeliveryCoordinator(
      store: store,
      commands: outcomeCommands,
      clock: () => now,
    );

    final delivery = await failing.submit(request(text: 'same'));
    await failing.issueSubmit(delivery.id);

    expect(
      (await store.read(delivery.id))!.state,
      PromptDeliveryState.failed,
    );
    expect(outcomeCommands.submitAttempts, 1);
  });

  test('abort landing during the submitIssued persist writes nothing',
      () async {
    final gatedStore = _GatedSaveStore(store);
    final gated = PromptDeliveryCoordinator(
      store: gatedStore,
      commands: commands,
      clock: () => now,
    );

    final delivery = await gated.submit(request(text: 'same'));
    gatedStore.gateNextSave();
    final issuing = gated.issueSubmit(delivery.id);
    // The abort lands while the `submitIssued` persist is still unresolved.
    gated.invalidateSubmittedDelivery(delivery.id);
    gatedStore.releaseAll();
    final result = await issuing;

    expect(result, PromptSubmissionResult.dropped);
    expect(commands.writes, isEmpty);
    expect(
      (await store.read(delivery.id))!.state,
      PromptDeliveryState.submittedUnknown,
    );
  });

  test('file-backed records keep their transitions across reopen', () async {
    final fs = InMemoryFilesystem();
    final persisted = FilePromptDeliveryStore(root: '/deliveries', fs: fs);
    final first = PromptDeliveryCoordinator(
      store: persisted,
      commands: commands,
      clock: () => now,
    );

    final delivery = await first.submit(request(text: 'same'));
    await first.issueSubmit(delivery.id);
    final writesBeforeRestore = commands.writes.length;

    final reopened = PromptDeliveryCoordinator(
      store: FilePromptDeliveryStore(root: '/deliveries', fs: fs),
      commands: commands,
      clock: () => now,
    );
    await reopened.restoreSeat(seat);

    final record =
        (await FilePromptDeliveryStore(root: '/deliveries', fs: fs)
                .forSeat(seat))
            .single;
    expect(record.state, PromptDeliveryState.submittedUnknown);
    expect(commands.writes.length, writesBeforeRestore);
    expect(commands.writes.last, 'submit:${delivery.id}');
  });
}

final class _GatedSaveStore implements PromptDeliveryStore {
  _GatedSaveStore(this._inner);

  final PromptDeliveryStore _inner;
  Completer<void>? _gate;

  /// Holds the NEXT save until [releaseAll].
  void gateNextSave() => _gate = Completer<void>();

  void releaseAll() {
    _gate?.complete();
    _gate = null;
  }

  @override
  Future<void> save(PromptDelivery delivery) async {
    final gate = _gate;
    if (gate != null) {
      _gate = null;
      await gate.future;
    }
    await _inner.save(delivery);
  }

  @override
  Future<PromptDelivery?> read(String id) => _inner.read(id);

  @override
  Future<List<PromptDelivery>> activeFor(RuntimeSeatKey seat) =>
      _inner.activeFor(seat);

  @override
  Future<List<PromptDelivery>> forSeat(RuntimeSeatKey seat) =>
      _inner.forSeat(seat);

  @override
  Future<Set<RuntimeSeatKey>> seatsForSession(String sessionId) =>
      _inner.seatsForSession(sessionId);
}

final class _OutcomePromptDeliveryCommands implements PromptDeliveryCommands {
  _OutcomePromptDeliveryCommands(this.outcome);

  final PromptSubmissionResult outcome;
  var submitAttempts = 0;

  @override
  Future<void> stage(
    PromptDelivery delivery, {
    required bool Function() canExecute,
  }) async {}

  @override
  Future<PromptSubmissionResult> submit(
    PromptDelivery delivery, {
    required bool Function() canExecute,
  }) async {
    submitAttempts++;
    return outcome;
  }
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
