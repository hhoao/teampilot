import 'dart:convert';
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

  test('OscTitle scanner is not fed without a subscriber', () {
    var titles = <String>[];
    bus.dispatchOutput(_osc('Cursor Agent'));
    expect(titles, isEmpty);
    final sub = bus.subscribe<OscTitle>((e) => titles.add(e.title));
    bus.dispatchOutput(_osc('Cursor - action required'));
    expect(titles, ['Cursor - action required']);
    sub.cancel();
    bus.dispatchOutput(_osc('ignored after unbind'));
    expect(titles, ['Cursor - action required']);
  });

  test('two OscTitle subscribers share one scan', () {
    final a = <String>[];
    final b = <String>[];
    bus.subscribe<OscTitle>((e) => a.add(e.title));
    bus.subscribe<OscTitle>((e) => b.add(e.title));
    bus.dispatchOutput(_osc('Hello'));
    expect(a, ['Hello']);
    expect(b, ['Hello']);
  });

  test('UserLineSubmitted fires on Enter from original input', () {
    final lines = <String>[];
    bus.subscribe<UserLineSubmitted>((e) => lines.add(e.line));
    bus.addInputTransform(_DropAll(order: 100));
    bus.transformInput(Uint8List.fromList(utf8.encode('hi\r')));
    expect(lines, ['hi']);
  });

  test('UserLineSubmitted tolerates malformed UTF-8 before Enter', () {
    final lines = <String>[];
    bus.subscribe<UserLineSubmitted>((e) => lines.add(e.line));
    bus.transformInput(
      Uint8List.fromList([0xFF, 0xFE, ...utf8.encode('hi'), 0x0D]),
    );
    expect(lines, hasLength(1));
    expect(lines.single, contains('hi'));
  });

  test('throwing OscTitle handler does not skip a second subscriber', () {
    final later = <String>[];
    bus.subscribe<OscTitle>((e) {
      throw StateError('handler failed');
    });
    bus.subscribe<OscTitle>((e) => later.add(e.title));
    bus.dispatchOutput(_osc('Hello'));
    expect(later, ['Hello']);
  });
}

Uint8List _osc(String title) =>
    Uint8List.fromList(utf8.encode('\x1b]0;$title\x07'));

final class _DropAll implements TerminalInputTransform {
  _DropAll({required this.order});

  @override
  final int order;

  @override
  Uint8List transform(Uint8List bytes, TerminalObservationSeat seat) {
    return Uint8List(0);
  }
}
