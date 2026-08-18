import 'dart:async';

/// Coordinates provider-ID usage mutations with configuration deletions.
class ManagedProviderIdDeletionBarrier {
  ManagedProviderIdDeletionBarrier._();

  static final Map<String, _ProviderIdState> _states = {};
  static Future<void> _deletionTail = Future<void>.value();

  static Future<bool> runUsageMutation(
    String providerId,
    Future<void> Function() mutation,
  ) async {
    final id = providerId.trim();
    if (id.isEmpty) return false;
    final state = _states.putIfAbsent(id, _ProviderIdState.new);
    if (state.deleting) {
      await state.deletionDone!.future;
      final error = state.deletionError;
      if (error != null) {
        Error.throwWithStackTrace(
          error,
          state.deletionStack ?? StackTrace.current,
        );
      }
      return false;
    }
    state.activeMutations++;
    try {
      await mutation();
      return true;
    } finally {
      state.activeMutations--;
      state.completeWhenIdle();
    }
  }

  static Future<void> runDeletion(
    Iterable<String> providerIds,
    Future<void> Function() deletion,
  ) async {
    final ids =
        providerIds
            .map((providerId) => providerId.trim())
            .where((id) => id.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    if (ids.isEmpty) {
      await deletion();
      return;
    }

    final previous = _deletionTail;
    final gate = Completer<void>();
    _deletionTail = gate.future;
    try {
      await previous;
      final states = [
        for (final id in ids) _states.putIfAbsent(id, _ProviderIdState.new),
      ];
      for (final state in states) {
        state.deleting = true;
        state.deletionDone = Completer<void>();
        state.deletionError = null;
        state.deletionStack = null;
      }
      try {
        await Future.wait([for (final state in states) state.waitForIdle()]);
        await deletion();
      } catch (error, stack) {
        for (final state in states) {
          state.deletionError = error;
          state.deletionStack = stack;
        }
        rethrow;
      } finally {
        for (var i = 0; i < states.length; i++) {
          final state = states[i];
          state.deleting = false;
          state.deletionDone!.complete();
          state.deletionDone = null;
          if (state.activeMutations == 0) _states.remove(ids[i]);
        }
      }
    } finally {
      if (!gate.isCompleted) gate.complete();
    }
  }
}

class _ProviderIdState {
  bool deleting = false;
  int activeMutations = 0;
  Completer<void>? deletionDone;
  Object? deletionError;
  StackTrace? deletionStack;
  Completer<void>? _idle;

  Future<void> waitForIdle() {
    if (activeMutations == 0) return Future<void>.value();
    _idle ??= Completer<void>();
    return _idle!.future;
  }

  void completeWhenIdle() {
    if (activeMutations == 0 && !(_idle?.isCompleted ?? true)) {
      _idle!.complete();
      _idle = null;
    }
  }
}
