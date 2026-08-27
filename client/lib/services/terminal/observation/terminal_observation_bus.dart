import 'dart:async';
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
  var _nextBindSequence = 0;
  final List<_OutputObserverEntry> _outputObservers = [];
  final List<TerminalInputObserver> _inputObservers = [];
  final List<_InputTransformEntry> _inputTransforms = [];
  final List<TerminalScreenObserver> _screenObservers = [];
  final List<void Function(int code)> _processExitObservers = [];
  final StreamController<void> _painted = StreamController<void>.broadcast();

  int get generation => _generation;

  Stream<void> get painted => _painted.stream;

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

  TerminalObservationSubscription addInputObserver(
    TerminalInputObserver observer,
  ) {
    _inputObservers.add(observer);
    return _CallbackSubscription(() {
      _inputObservers.remove(observer);
    });
  }

  TerminalObservationSubscription addInputTransform(
    TerminalInputTransform transform,
  ) {
    final entry = _InputTransformEntry(
      transform: transform,
      bindSequence: _nextBindSequence++,
    );
    _inputTransforms.add(entry);
    return _CallbackSubscription(() {
      _inputTransforms.remove(entry);
    });
  }

  Uint8List transformInput(Uint8List bytes) {
    if (_disposed) return bytes;
    final view = bytes.asUnmodifiableView();
    final observers = List<TerminalInputObserver>.from(_inputObservers);
    for (final observer in observers) {
      try {
        observer.onInput(view, seat);
      } catch (error, stackTrace) {
        AppLogger.instance.e(
          'TerminalObservationBus input observer failed',
          error: error,
          stackTrace: stackTrace,
          recordError: false,
        );
      }
    }

    final transforms = List<_InputTransformEntry>.from(_inputTransforms)
      ..sort((a, b) {
        final byOrder = a.transform.order.compareTo(b.transform.order);
        if (byOrder != 0) return byOrder;
        return a.bindSequence.compareTo(b.bindSequence);
      });
    var current = bytes;
    for (final entry in transforms) {
      try {
        current = entry.transform.transform(current, seat);
      } catch (error, stackTrace) {
        AppLogger.instance.e(
          'TerminalObservationBus input transform failed',
          error: error,
          stackTrace: stackTrace,
          recordError: false,
        );
      }
    }
    return current;
  }

  TerminalObservationSubscription addScreenObserver(
    TerminalScreenObserver observer,
  ) {
    _screenObservers.add(observer);
    return _CallbackSubscription(() {
      _screenObservers.remove(observer);
    });
  }

  void notifyPainted() {
    if (_disposed) return;
    final observers = List<TerminalScreenObserver>.from(_screenObservers);
    for (final observer in observers) {
      try {
        observer.onPainted(seat);
      } catch (error, stackTrace) {
        AppLogger.instance.e(
          'TerminalObservationBus screen observer failed',
          error: error,
          stackTrace: stackTrace,
          recordError: false,
        );
      }
    }
    if (_painted.hasListener) {
      _painted.add(null);
    }
  }

  TerminalObservationSubscription addProcessExitObserver(
    void Function(int code) observer,
  ) {
    _processExitObservers.add(observer);
    return _CallbackSubscription(() {
      _processExitObservers.remove(observer);
    });
  }

  void notifyProcessExited(int code) {
    if (_disposed) return;
    final observers = List<void Function(int code)>.from(_processExitObservers);
    for (final observer in observers) {
      try {
        observer(code);
      } catch (error, stackTrace) {
        AppLogger.instance.e(
          'TerminalObservationBus process-exit observer failed',
          error: error,
          stackTrace: stackTrace,
          recordError: false,
        );
      }
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _generation++;
    _outputObservers.clear();
    _inputObservers.clear();
    _inputTransforms.clear();
    _screenObservers.clear();
    _processExitObservers.clear();
    unawaited(_painted.close());
  }
}

final class _OutputObserverEntry {
  _OutputObserverEntry({required this.observer, required this.phases});

  final TerminalOutputObserver observer;
  final Set<TerminalLaunchPhase> phases;
}

final class _InputTransformEntry {
  _InputTransformEntry({required this.transform, required this.bindSequence});

  final TerminalInputTransform transform;
  final int bindSequence;
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
