import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/event/dispatcher.dart';

enum _TestKind { a, b }

class _TestEvent implements DispatcherEvent<_TestKind> {
  const _TestEvent(this.eventKind, this.timestamp);

  @override
  final _TestKind eventKind;
  @override
  final DateTime timestamp;
}

class _RecordingHandler implements EventHandler<_TestEvent> {
  final events = <_TestEvent>[];

  @override
  void handle(_TestEvent event) => events.add(event);
}

class _StubDispatcher implements Dispatcher {
  final dispatched = <DispatcherEvent>[];
  final registered = <EventHandler<dynamic>>[];

  @override
  void dispatch(DispatcherEvent event) => dispatched.add(event);

  @override
  void registerFamily<K extends Enum>(Type kindType, EventHandler handler) =>
      registered.add(handler);

  @override
  void unregister(EventHandler handler) {}
}

void main() {
  test('interfaces compile and are implementable', () {
    final d = _StubDispatcher();
    final e = _TestEvent(_TestKind.a, DateTime(2026));
    // ignore: unnecessary_type_check
    expect(e is DispatcherEvent<_TestKind>, isTrue);
    expect(d, isA<Dispatcher>());
  });

  test('dispatcher accepts events and family registrations', () {
    final d = _StubDispatcher();
    final handler = _RecordingHandler();
    final event = _TestEvent(_TestKind.b, DateTime(2026));

    d.registerFamily<_TestKind>(_TestKind, handler);
    d.dispatch(event);

    expect(d.registered, contains(handler));
    expect(d.dispatched, contains(event));
    expect(handler.events, isEmpty);
  });
}
