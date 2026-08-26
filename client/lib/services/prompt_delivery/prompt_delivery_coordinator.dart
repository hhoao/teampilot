import 'dart:async';
import 'dart:math';

import '../agent_runtime/runtime_event.dart';
import 'prompt_delivery.dart';
import 'prompt_delivery_store.dart';

/// The write boundary consumed by terminal adapters. The coordinator persists
/// state before invoking either operation and never invokes it on restore.
abstract interface class PromptDeliveryCommands {
  Future<void> stage(
    PromptDelivery delivery, {
    required bool Function() canExecute,
  });

  Future<void> submit(
    PromptDelivery delivery, {
    required bool Function() canExecute,
  });
}

/// Serializes delivery state per runtime seat and owns its durable lifecycle.
final class PromptDeliveryCoordinator {
  PromptDeliveryCoordinator({
    required this.store,
    required this.commands,
    String Function()? idGenerator,
    DateTime Function()? clock,
  }) : _idGenerator = idGenerator ?? _newId,
       _clock = clock ?? DateTime.now;

  final PromptDeliveryStore store;
  final PromptDeliveryCommands commands;
  final String Function() _idGenerator;
  final DateTime Function() _clock;
  final Map<RuntimeSeatKey, Future<void>> _seatTails = {};
  final Map<String, PromptDeliveryState> _liveStates = {};

  /// Creates the only non-terminal delivery allowed for [request.seat].
  Future<PromptDelivery> submit(PromptDeliveryRequest request) => _serialized(
    request.seat,
    () async {
      final active = await store.activeFor(request.seat);
      if (active.isNotEmpty) {
        throw StateError('A prompt delivery is already active for this seat.');
      }
      final history = await store.forSeat(request.seat);
      final now = _clock();
      final normalizedText = normalizePromptText(request.text);
      final delivery = PromptDelivery(
        id: _idGenerator(),
        seat: request.seat,
        cli: request.cli,
        text: request.text,
        normalizedText: normalizedText,
        promptEpoch: _nextEpoch(history),
        state: PromptDeliveryState.created,
        createdAt: now,
        updatedAt: now,
        acceptsWeakConfirmation: !history.any(
          (delivery) =>
              _couldHaveIssuedSubmit(delivery) &&
              delivery.normalizedText == normalizedText,
        ),
      );
      await store.save(delivery);
      _liveStates[delivery.id] = delivery.state;
      return delivery;
    },
  );

  /// Records input readiness. Staging and submit effects remain opt-in so a
  /// terminal adapter may install a queue fence before it requests them.
  Future<PromptDelivery> waitForInputSurface(String id) => _update(
    id,
    allowed: const {PromptDeliveryState.created},
    next: PromptDeliveryState.waitingForInputSurface,
  );

  /// Persists `staged` before asking the terminal adapter to paste text.
  Future<PromptDelivery> stage(String id) async {
    final delivery = await _update(
      id,
      allowed: const {
        PromptDeliveryState.created,
        PromptDeliveryState.waitingForInputSurface,
      },
      next: PromptDeliveryState.staged,
    );
    await commands.stage(
      delivery,
      canExecute: () => canExecute(id, PromptDeliveryState.staged),
    );
    return delivery;
  }

  /// Persists `submitIssued` before asking the terminal adapter to issue CR.
  Future<PromptDelivery> issueSubmit(String id) async {
    final delivery = await _update(
      id,
      allowed: const {
        PromptDeliveryState.created,
        PromptDeliveryState.waitingForInputSurface,
        PromptDeliveryState.staged,
      },
      next: PromptDeliveryState.submitIssued,
    );
    await commands.submit(
      delivery,
      canExecute: () => canExecute(id, PromptDeliveryState.submitIssued),
    );
    return delivery;
  }

  /// The synchronous fence terminal queues consult immediately before a PTY
  /// write. It changes only after the replacement record has been persisted.
  bool canExecute(String id, PromptDeliveryState expectedState) =>
      _liveStates[id] == expectedState;

  /// Applies one already-journaled runtime event. Event handling is seat
  /// serialized with creation and transitions to avoid same-text races.
  Future<void> onRuntimeEvent(RuntimeEventEnvelope event) {
    if (event.kind != RuntimeEventKind.promptSubmitted) return Future.value();
    return _serialized(event.seat, () => _confirmFrom(event));
  }

  Future<void> _confirmFrom(RuntimeEventEnvelope event) async {
    if (event.correlationStrength == RuntimeCorrelationStrength.exact) {
      final exactId = _eventDeliveryId(event);
      if (exactId == null) return;
      final delivery = await store.read(exactId);
      if (delivery != null &&
          delivery.seat == event.seat &&
          delivery.cli == event.cli &&
          delivery.state == PromptDeliveryState.submitIssued) {
        await _confirm(delivery);
      }
      return;
    }

    final active = await store.activeFor(event.seat);
    if (active.length != 1) return;
    final delivery = active.single;
    if (delivery.cli != event.cli ||
        delivery.state != PromptDeliveryState.submitIssued ||
        !delivery.acceptsWeakConfirmation ||
        delivery.normalizedText != normalizePromptText(event.prompt ?? '')) {
      return;
    }
    await _confirm(delivery);
  }

  /// Recovery never replays staging or submit commands. A prior CR might have
  /// reached the process, so it becomes explicitly unresolved instead.
  Future<void> restoreSeat(RuntimeSeatKey seat) => _serialized(seat, () async {
    for (final delivery in await store.activeFor(seat)) {
      _liveStates[delivery.id] = delivery.state;
      if (delivery.state == PromptDeliveryState.submitIssued) {
        await _transition(delivery, PromptDeliveryState.submittedUnknown);
      }
    }
  });

  Future<PromptDelivery> failBeforeSubmit(String id, {String? reason}) =>
      _update(
        id,
        allowed: const {
          PromptDeliveryState.created,
          PromptDeliveryState.waitingForInputSurface,
          PromptDeliveryState.staged,
        },
        next: PromptDeliveryState.failed,
        failureReason: reason,
      );

  Future<PromptDelivery> markSubmittedUnknown(String id) => _update(
    id,
    allowed: const {PromptDeliveryState.submitIssued},
    next: PromptDeliveryState.submittedUnknown,
  );

  /// Immediately drops the live submit fence, then persists the unresolved
  /// outcome. This is used by an interrupt that races a queued PTY write: the
  /// queue must observe the invalidation synchronously, while the durable
  /// transition still records that a prior CR may already have reached the
  /// process.
  void invalidateSubmittedDelivery(String id) {
    if (_liveStates[id] != PromptDeliveryState.submitIssued) return;
    _liveStates[id] = PromptDeliveryState.submittedUnknown;
    unawaited(
      _update(
        id,
        allowed: const {PromptDeliveryState.submitIssued},
        next: PromptDeliveryState.submittedUnknown,
      ).then<void>((_) {}, onError: (Object _, StackTrace __) {}),
    );
  }

  Future<void> _confirm(PromptDelivery delivery) async {
    await _transition(delivery, PromptDeliveryState.confirmed);
  }

  Future<PromptDelivery> _update(
    String id, {
    required Set<PromptDeliveryState> allowed,
    required PromptDeliveryState next,
    String? failureReason,
  }) async {
    final current = await store.read(id);
    if (current == null) throw StateError('Unknown prompt delivery: $id');
    return _serialized(current.seat, () async {
      final fresh = await store.read(id);
      if (fresh == null) throw StateError('Unknown prompt delivery: $id');
      if (!allowed.contains(fresh.state)) {
        throw StateError(
          'Cannot transition ${fresh.state.name} to ${next.name}.',
        );
      }
      return _transition(fresh, next, failureReason: failureReason);
    });
  }

  Future<PromptDelivery> _transition(
    PromptDelivery current,
    PromptDeliveryState next, {
    String? failureReason,
  }) async {
    final nextRecord = current.copyWith(
      state: next,
      updatedAt: _clock(),
      failureReason: failureReason,
      clearFailureReason: next != PromptDeliveryState.failed,
    );
    await store.save(nextRecord);
    _liveStates[nextRecord.id] = nextRecord.state;
    return nextRecord;
  }

  Future<T> _serialized<T>(RuntimeSeatKey seat, Future<T> Function() action) {
    final previous = _seatTails[seat] ?? Future<void>.value();
    final result = previous.then((_) => action());
    final tail = result.then<void>((_) {}, onError: (_) {});
    _seatTails[seat] = tail;
    unawaited(
      tail.then((_) {
        if (identical(_seatTails[seat], tail)) _seatTails.remove(seat);
      }),
    );
    return result;
  }
}

int _nextEpoch(List<PromptDelivery> history) =>
    history.fold(0, (largest, delivery) => max(largest, delivery.promptEpoch)) +
    1;

bool _couldHaveIssuedSubmit(PromptDelivery delivery) =>
    delivery.state == PromptDeliveryState.submitIssued ||
    delivery.state == PromptDeliveryState.confirmed ||
    delivery.state == PromptDeliveryState.submittedUnknown;

String? _eventDeliveryId(RuntimeEventEnvelope event) {
  final raw = event.raw;
  if (raw == null) return null;
  final id = raw['deliveryId'] ?? raw['delivery_id'];
  final normalized = id?.toString().trim() ?? '';
  return normalized.isEmpty ? null : normalized;
}

String _newId() {
  final random = Random.secure();
  final randomPart = List<int>.generate(
    12,
    (_) => random.nextInt(256),
  ).map((value) => value.toRadixString(16).padLeft(2, '0')).join();
  return 'delivery-${DateTime.now().microsecondsSinceEpoch}-$randomPart';
}
