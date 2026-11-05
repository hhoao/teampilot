import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/ssh/worker/ssh_worker_forward_pump.dart';
import 'package:teampilot/services/ssh/worker/ssh_worker_protocol.dart';

void main() {
  test(
    'forward pump streams ordered bytes, acknowledges, and closes once',
    () async {
      final channel = _FakeForwardChannel();
      final events = <SshWorkerEvent>[];
      var finished = 0;
      final pump = SshWorkerForwardPump(
        id: 'forward-1',
        channel: channel,
        sendEvent: events.add,
        onFinished: (_) => finished++,
        outputWindow: 1,
      )..start();

      channel.emit([1, 2]);
      await Future<void>.delayed(Duration.zero);
      pump.acknowledge(0);
      channel.emit([3]);
      await Future<void>.delayed(Duration.zero);
      await pump.close();
      await pump.close();

      expect(events.map((event) => event.bytes), [
        [1, 2],
        [3],
        isEmpty,
      ]);
      expect(events.map((event) => event.sequence), [0, 1, 2]);
      expect(events.last.isFinal, isTrue);
      expect(channel.closeCount, 1);
      expect(finished, 1);
    },
  );

  test(
    'forward pump holds later chunks until the window is acknowledged',
    () async {
      final channel = _FakeForwardChannel();
      final events = <SshWorkerEvent>[];
      final pump = SshWorkerForwardPump(
        id: 'forward-1',
        channel: channel,
        sendEvent: events.add,
        onFinished: (_) {},
        outputWindow: 1,
      )..start();

      channel.emit([1]);
      channel.emit([2]);
      await Future<void>.delayed(Duration.zero);
      expect(events.map((event) => event.bytes), [
        [1],
      ]);

      pump.acknowledge(0);
      await Future<void>.delayed(Duration.zero);
      expect(events.map((event) => event.bytes), [
        [1],
        [2],
      ]);
      await pump.close();
    },
  );

  test('forward EOF drains within the ACK window', () async {
    final channel = _FakeForwardChannel();
    final events = <SshWorkerEvent>[];
    final pump = SshWorkerForwardPump(
      id: 'forward-1',
      channel: channel,
      sendEvent: events.add,
      onFinished: (_) {},
      outputWindow: 1,
    )..start();

    channel.emit([1]);
    channel.emit([2]);
    channel.finishStream();
    await Future<void>.delayed(Duration.zero);
    expect(events, hasLength(1));

    pump.acknowledge(0);
    await pump.done;

    expect(events.map((event) => event.bytes), [
      [1],
      [2],
      isEmpty,
    ]);
    expect(events.last.isFinal, isTrue);
  });

  test('forward pump turns input errors into an error final event', () async {
    final channel = _FakeForwardChannel();
    final events = <SshWorkerEvent>[];
    final pump = SshWorkerForwardPump(
      id: 'forward-1',
      channel: channel,
      sendEvent: events.add,
      onFinished: (_) {},
    )..start();

    channel.fail(StateError('channel failed'));
    await pump.done;

    expect(events, hasLength(1));
    expect(events.single.isFinal, isTrue);
    expect(events.single.bytes, isEmpty);
    expect(events.single.errorCode, 'transport_error');
  });
}

final class _FakeForwardChannel implements SshWorkerForwardChannel {
  final _stream = StreamController<Uint8List>();
  var closeCount = 0;

  @override
  Stream<Uint8List> get stream => _stream.stream;

  @override
  void add(Uint8List data) {}

  @override
  Future<void> close() async {
    closeCount++;
    await _stream.close();
  }

  void emit(List<int> bytes) => _stream.add(Uint8List.fromList(bytes));

  void fail(Object error) => _stream.addError(error);

  void finishStream() => unawaited(_stream.close());
}
