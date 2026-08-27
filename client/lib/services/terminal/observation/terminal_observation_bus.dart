import 'dart:typed_data';

import '../../../utils/logging/logger.dart';
import '../terminal_launch_phase.dart';
import 'terminal_observation_events.dart';
import 'terminal_observation_seat.dart';

/// Seat-scoped PTY observation registry: register → dispatch → handle.
final class TerminalObservationBus {
  TerminalObservationBus({required this.seat});

  final TerminalObservationSeat seat;

  int _generation = 1;
  var _disposed = false;
  final List<_OutputObserverEntry> _outputObservers = [];

  int get generation => _generation;

  void setPhase(TerminalLaunchPhase phase) {
    seat.phase = phase;
  }

  TerminalObservationSubscription addOutputObserver(
    TerminalOutputObserver observer, {
    required Set<TerminalLaunchPhase> phases,
  }) {
    final entry = _OutputObserverEntry(observer: observer, phases: phases);
    _outputObservers.add(entry);
    return _CallbackSubscription(() {
      _outputObservers.remove(entry);
    });
  }

  void dispatchOutput(Uint8List bytes) {
    if (_disposed || bytes.isEmpty) return;
    final dispatchPhase = seat.phase;
    final view = bytes.asUnmodifiableView();
    final observers = List<_OutputObserverEntry>.from(_outputObservers);
    for (final entry in observers) {
      if (!entry.phases.contains(dispatchPhase)) continue;
      try {
        entry.observer.onOutput(view, seat);
      } catch (error, stackTrace) {
        AppLogger.instance.e(
          'TerminalObservationBus output observer failed',
          error: error,
          stackTrace: stackTrace,
          recordError: false,
        );
      }
    }
  }

  void notifyPainted() {}

  TerminalObservationSubscription addInputObserver(
    TerminalInputObserver observer,
  ) {
    return _CallbackSubscription(() {});
  }

  TerminalObservationSubscription addInputTransform(
    TerminalInputTransform transform,
  ) {
    return _CallbackSubscription(() {});
  }

  Uint8List transformInput(Uint8List bytes) => bytes;

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _generation++;
    _outputObservers.clear();
  }
}

final class _OutputObserverEntry {
  _OutputObserverEntry({required this.observer, required this.phases});

  final TerminalOutputObserver observer;
  final Set<TerminalLaunchPhase> phases;
}

final class _CallbackSubscription implements TerminalObservationSubscription {
  _CallbackSubscription(this._cancel);

  final void Function() _cancel;
  var _done = false;

  @override
  void cancel() {
    if (_done) return;
    _done = true;
    _cancel();
  }
}
