import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/agent_attention_cubit.dart';
import 'package:teampilot/services/agent_status/agent_attention_state.dart';
import 'package:teampilot/services/cli/cursor/capabilities/terminal_behavior.dart';
import 'package:teampilot/services/terminal/observation/terminal_observation_bus.dart';
import 'package:teampilot/services/terminal/observation/terminal_observation_events.dart';
import 'package:teampilot/services/terminal/observation/terminal_observation_seat.dart';
import 'package:teampilot/services/terminal/terminal_launch_phase.dart';

void main() {
  late AgentAttentionCubit attention;
  late bool skipPermissions;
  late TerminalObservationSeat seat;
  late TerminalObservationBus bus;

  setUp(() {
    attention = AgentAttentionCubit(pruneInterval: null);
    skipPermissions = false;
    seat = TerminalObservationSeat(
      sessionId: 's',
      memberId: 'm',
      phase: TerminalLaunchPhase.running,
      attention: attention,
      skipPermissions: () => skipPermissions,
    );
    bus = TerminalObservationBus(seat: seat);
  });

  tearDown(() {
    bus.dispose();
    attention.close();
  });

  Uint8List osc(String title) =>
      Uint8List.fromList(utf8.encode('\x1b]0;$title\x07'));

  test('action-required OSC title → waiting', () {
    const CursorTerminalBehavior().bind(bus, seat);
    bus.dispatchOutput(osc('Cursor - action required'));
    expect(
      attention.state.attentionFor(sessionId: 's', memberId: 'm'),
      AgentSeatAttention.waiting,
    );
  });

  test('bare Cursor Agent never marks waiting', () {
    const CursorTerminalBehavior().bind(bus, seat);
    bus.dispatchOutput(osc('Cursor Agent'));
    expect(
      attention.state.attentionFor(sessionId: 's', memberId: 'm'),
      isNull,
    );
  });

  test('non-matching title after waiting clears to done', () {
    const CursorTerminalBehavior().bind(bus, seat);
    bus.dispatchOutput(osc('Cursor - action required'));
    bus.dispatchOutput(osc('Cursor ready'));
    expect(
      attention.state.attentionFor(sessionId: 's', memberId: 'm'),
      AgentSeatAttention.done,
    );
  });

  test('bare title after waiting does not clear', () {
    const CursorTerminalBehavior().bind(bus, seat);
    bus.dispatchOutput(osc('Cursor - action required'));
    bus.dispatchOutput(osc('Cursor Agent'));
    expect(
      attention.state.attentionFor(sessionId: 's', memberId: 'm'),
      AgentSeatAttention.waiting,
    );
  });

  test('YOLO skipPermissions does not surface waiting', () {
    skipPermissions = true;
    const CursorTerminalBehavior().bind(bus, seat);
    bus.dispatchOutput(osc('Cursor - action required'));
    expect(
      attention.state.attentionFor(sessionId: 's', memberId: 'm'),
      isNull,
    );
  });

  test('OSC 997 is stripped at transform order 200', () {
    const CursorTerminalBehavior().bind(bus, seat);
    final before = <Uint8List>[];
    final after = <Uint8List>[];
    bus.addInputTransform(_Capture(order: 199, seen: before));
    bus.addInputTransform(_Capture(order: 201, seen: after));
    final report = Uint8List.fromList([
      0x1b, 0x5d, 0x39, 0x39, 0x37, 0x3b, 0x31, 0x07,
    ]);
    expect(bus.transformInput(report), isEmpty);
    expect(before, [report]);
    expect(after.single, isEmpty);
  });
}

final class _Capture implements TerminalInputTransform {
  _Capture({required this.order, required this.seen});

  @override
  final int order;
  final List<Uint8List> seen;

  @override
  Uint8List transform(Uint8List bytes, TerminalObservationSeat seat) {
    seen.add(Uint8List.fromList(bytes));
    return bytes;
  }
}
