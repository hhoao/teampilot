import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/terminal/observation/terminal_observation_bus.dart';
import 'package:teampilot/services/terminal/observation/terminal_observation_events.dart';
import 'package:teampilot/services/terminal/observation/terminal_observation_seat.dart';
import 'package:teampilot/services/terminal/terminal_launch_phase.dart';

void main() {
  late TerminalObservationSeat seat;
  late TerminalObservationBus bus;

  setUp(() {
    seat = TerminalObservationSeat(
      sessionId: 's',
      memberId: 'm',
      phase: TerminalLaunchPhase.running,
    );
    bus = TerminalObservationBus(seat: seat);
  });

  tearDown(() => bus.dispose());

  test('input observers see original bytes before transforms', () {
    final seen = <int>[];
    bus.addInputObserver(_InputCapture(seen));
    bus.addInputTransform(_ZeroFirst(order: 100));
    final out = bus.transformInput(Uint8List.fromList([1, 2]));
    expect(seen, [1]);
    expect(out, [0, 2]);
  });

  test('transforms run by ascending order; equal order keeps bind sequence', () {
    bus.addInputTransform(_Append(order: 200, suffix: 2));
    bus.addInputTransform(_Append(order: 100, suffix: 1));
    bus.addInputTransform(_Append(order: 100, suffix: 9));
    expect(bus.transformInput(Uint8List.fromList([0])), [0, 1, 9, 2]);
  });

  test('throwing transform is skipped; later transform still runs', () {
    bus.addInputTransform(_ThrowingTransform(order: 100));
    bus.addInputTransform(_Append(order: 200, suffix: 7));
    expect(bus.transformInput(Uint8List.fromList([1])), [1, 7]);
  });

  test('throwing input observer does not skip later transform', () {
    bus.addInputObserver(_ThrowingInput());
    bus.addInputTransform(_Append(order: 100, suffix: 7));
    expect(bus.transformInput(Uint8List.fromList([1])), [1, 7]);
  });

  test('empty transform result is returned as empty', () {
    bus.addInputTransform(_DropAll(order: 100));
    expect(bus.transformInput(Uint8List.fromList([1, 2])), isEmpty);
  });

  test('notifyPainted fans out to screen observers', () {
    var paints = 0;
    bus.addScreenObserver(_Paint(() => paints++));
    bus.notifyPainted();
    expect(paints, 1);
  });

  test('painted stream emits once then no-ops after dispose', () async {
    var count = 0;
    final sub = bus.painted.listen((_) => count++);
    addTearDown(sub.cancel);
    bus.notifyPainted();
    await pumpEventQueue();
    expect(count, 1);
    bus.dispose();
    expect(() => bus.notifyPainted(), returnsNormally);
    await pumpEventQueue();
    expect(count, 1);
  });

  test('notifyProcessExited fans out after dispose no-ops', () {
    final codes = <int>[];
    bus.addProcessExitObserver((code) => codes.add(code));
    bus.notifyProcessExited(3);
    expect(codes, [3]);
    bus.dispose();
    bus.notifyProcessExited(4);
    expect(codes, [3]);
  });
}

final class _InputCapture implements TerminalInputObserver {
  _InputCapture(this.seen);
  final List<int> seen;

  @override
  void onInput(Uint8List bytes, TerminalObservationSeat seat) {
    seen.add(bytes[0]);
  }
}

final class _ThrowingInput implements TerminalInputObserver {
  @override
  void onInput(Uint8List bytes, TerminalObservationSeat seat) {
    throw StateError('input observer failed');
  }
}

final class _ZeroFirst implements TerminalInputTransform {
  _ZeroFirst({required this.order});

  @override
  final int order;

  @override
  Uint8List transform(Uint8List bytes, TerminalObservationSeat seat) {
    final out = Uint8List.fromList(bytes);
    if (out.isNotEmpty) out[0] = 0;
    return out;
  }
}

final class _Append implements TerminalInputTransform {
  _Append({required this.order, required this.suffix});

  @override
  final int order;
  final int suffix;

  @override
  Uint8List transform(Uint8List bytes, TerminalObservationSeat seat) {
    return Uint8List.fromList([...bytes, suffix]);
  }
}

final class _ThrowingTransform implements TerminalInputTransform {
  _ThrowingTransform({required this.order});

  @override
  final int order;

  @override
  Uint8List transform(Uint8List bytes, TerminalObservationSeat seat) {
    throw StateError('transform failed');
  }
}

final class _DropAll implements TerminalInputTransform {
  _DropAll({required this.order});

  @override
  final int order;

  @override
  Uint8List transform(Uint8List bytes, TerminalObservationSeat seat) {
    return Uint8List(0);
  }
}

final class _Paint implements TerminalScreenObserver {
  _Paint(this._onPainted);
  final void Function() _onPainted;

  @override
  void onPainted(TerminalObservationSeat seat) {
    _onPainted();
  }
}
