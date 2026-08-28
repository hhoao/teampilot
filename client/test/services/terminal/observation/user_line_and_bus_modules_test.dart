import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/team_bus/bus_user_line_capture.dart';
import 'package:teampilot/services/terminal/observation/modules/team_bus_intercept_module.dart';
import 'package:teampilot/services/terminal/observation/modules/user_line_module.dart';
import 'package:teampilot/services/terminal/observation/terminal_observation_bus.dart';
import 'package:teampilot/services/terminal/observation/terminal_observation_seat.dart';
import 'package:teampilot/services/terminal/pending_user_message.dart';
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

  test('user line is captured even when bus intercepts submit', () async {
    final lines = <String>[];
    UserLineModule(onEveryUserLineSubmitted: lines.add).bind(bus, seat);
    final module = TeamBusInterceptModule(
      routing: BusUserInputRouting(
        shouldIntercept: () => true,
        onTurnStart: () {},
        onUserLine: (line) => 'id-$line',
      ),
    );
    module.bind(bus, seat);
    expect(
      module.parkedUserSubmissions,
      emits(isA<PendingUserMessage>().having((m) => m.id, 'id', 'id-hello')),
    );
    bus.transformInput(Uint8List.fromList(utf8.encode('hello\r')));
    expect(lines, ['hello']);
  });

  test('first-line callback fires only once', () {
    final first = <String>[];
    UserLineModule(onFirstUserLineSubmitted: first.add).bind(bus, seat);
    bus.transformInput(Uint8List.fromList(utf8.encode('one\r')));
    bus.transformInput(Uint8List.fromList(utf8.encode('two\r')));
    expect(first, ['one']);
  });

  test('onTurnStart fires on UserLineSubmitted', () {
    var starts = 0;
    UserLineModule(onTurnStart: () => starts++).bind(bus, seat);
    bus.transformInput(Uint8List.fromList(utf8.encode('one\r')));
    bus.transformInput(Uint8List.fromList(utf8.encode('two\r')));
    expect(starts, 2);
  });

  test(
    'parked submissions emit when intercept returns a non-empty id',
    () async {
      final module = TeamBusInterceptModule(
        routing: BusUserInputRouting(
          shouldIntercept: () => true,
          onTurnStart: () {},
          onUserLine: (_) => 'mid',
        ),
      );
      module.bind(bus, seat);
      expect(
        module.parkedUserSubmissions,
        emits(isA<PendingUserMessage>().having((m) => m.id, 'id', 'mid')),
      );
      bus.transformInput(Uint8List.fromList(utf8.encode('x\r')));
    },
  );

  test('empty intercept id does not park a submission', () async {
    final module = TeamBusInterceptModule(
      routing: BusUserInputRouting(
        shouldIntercept: () => true,
        onTurnStart: () {},
        onUserLine: (_) => '',
      ),
    );
    module.bind(bus, seat);
    final parked = <PendingUserMessage>[];
    final sub = module.parkedUserSubmissions.listen(parked.add);
    addTearDown(sub.cancel);
    bus.transformInput(Uint8List.fromList(utf8.encode('x\r')));
    await pumpEventQueue();
    expect(parked, isEmpty);
  });

  test('unbind stops user-line callbacks', () {
    final lines = <String>[];
    UserLineModule(
      onEveryUserLineSubmitted: lines.add,
    ).bind(bus, seat).unbind();
    bus.transformInput(Uint8List.fromList(utf8.encode('hello\r')));
    expect(lines, isEmpty);
  });

  test('unbind cancels intercept without closing parked stream', () async {
    final module = TeamBusInterceptModule(
      routing: BusUserInputRouting(
        shouldIntercept: () => true,
        onTurnStart: () {},
        onUserLine: (_) => 'mid',
      ),
    );
    final binding = module.bind(bus, seat);
    var closed = false;
    final doneSub = module.parkedUserSubmissions.listen(
      (_) {},
      onDone: () => closed = true,
    );
    addTearDown(doneSub.cancel);
    binding.unbind();
    await pumpEventQueue();
    expect(closed, isFalse);

    final parked = <PendingUserMessage>[];
    final parkedSub = module.parkedUserSubmissions.listen(parked.add);
    addTearDown(parkedSub.cancel);
    bus.transformInput(Uint8List.fromList(utf8.encode('x\r')));
    await pumpEventQueue();
    expect(parked, isEmpty);
  });

  test('close closes the parked submissions stream', () async {
    final module = TeamBusInterceptModule(
      routing: BusUserInputRouting(
        shouldIntercept: () => true,
        onTurnStart: () {},
        onUserLine: (_) => 'mid',
      ),
    );
    var done = false;
    final sub = module.parkedUserSubmissions.listen(
      (_) {},
      onDone: () => done = true,
    );
    addTearDown(sub.cancel);
    await module.close();
    await pumpEventQueue();
    expect(done, isTrue);
  });

  test('isUnreadParkedMessage delegates to routing', () {
    final module = TeamBusInterceptModule(
      routing: BusUserInputRouting(
        shouldIntercept: () => true,
        onTurnStart: () {},
        onUserLine: (_) => 'mid',
        isUnread: (id) => id == 'unread',
      ),
    );
    expect(module.isUnreadParkedMessage('unread'), isTrue);
    expect(module.isUnreadParkedMessage('other'), isFalse);
  });
}
