import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/event/async_dispatcher.dart';
import 'package:teampilot/services/event/dispatcher.dart';

enum _FamKind { ping, pong }

enum _OtherKind { ping }

class _FamEvent implements DispatcherEvent<_FamKind> {
  const _FamEvent(this.kind, this.timestamp, [this.tag = '']);

  @override
  final _FamKind kind;
  @override
  final DateTime timestamp;
  final String tag;
}

class _OtherEvent implements DispatcherEvent<_OtherKind> {
  const _OtherEvent(this.kind, this.timestamp);

  @override
  final _OtherKind kind;
  @override
  final DateTime timestamp;
}

class _Recorder implements EventHandler<_FamEvent> {
  final tags = <String>[];

  @override
  void handle(_FamEvent event) => tags.add(event.tag);
}

class _ThrowingHandler implements EventHandler<_FamEvent> {
  @override
  void handle(_FamEvent event) => throw StateError('boom');
}

void main() {
  test('dispatch returns before handlers run; order preserved globally',
      () async {
    final d = AsyncDispatcher()..start();
    final r = _Recorder();
    d.registerFamily<_FamKind>(_FamKind, r);
    d.dispatch(_FamEvent(_FamKind.ping, DateTime(2026), 'a'));
    expect(r.tags, isEmpty); // enqueue-only, not yet consumed
    d.dispatch(_FamEvent(_FamKind.pong, DateTime(2026), 'b'));
    await d.stop(); // drains
    expect(r.tags, ['a', 'b']);
  });

  test('routes by family; unregistered families dropped silently', () async {
    final d = AsyncDispatcher()..start();
    final r = _Recorder();
    d.registerFamily<_FamKind>(_FamKind, r);
    // Unregistered family: dropped silently (YARN: no handler registered,
    // event is only logged).
    d.dispatch(_OtherEvent(_OtherKind.ping, DateTime(2026)));
    d.dispatch(_FamEvent(_FamKind.ping, DateTime(2026), 'a'));
    await d.stop();
    expect(r.tags, ['a']);
    expect(d.queued, 0);
  });

  test('multiple handlers for same family all invoked (multicast)', () async {
    final d = AsyncDispatcher()..start();
    final r1 = _Recorder();
    final r2 = _Recorder();
    d.registerFamily<_FamKind>(_FamKind, r1);
    d.registerFamily<_FamKind>(_FamKind, r2);
    d.dispatch(_FamEvent(_FamKind.ping, DateTime(2026), 'x'));
    await d.stop();
    expect(r1.tags, ['x']);
    expect(r2.tags, ['x']);
  });

  test('unregister stops delivery', () async {
    final d = AsyncDispatcher()..start();
    final r = _Recorder();
    d.registerFamily<_FamKind>(_FamKind, r);
    d.unregister(r);
    d.dispatch(_FamEvent(_FamKind.ping, DateTime(2026), 'x'));
    await d.stop();
    expect(r.tags, isEmpty);
  });

  test('handler exception is isolated; subsequent events still processed',
      () async {
    final d = AsyncDispatcher()..start();
    final good = _Recorder();
    d.registerFamily<_FamKind>(_FamKind, _ThrowingHandler());
    d.registerFamily<_FamKind>(_FamKind, good);
    d.dispatch(_FamEvent(_FamKind.ping, DateTime(2026), '1'));
    d.dispatch(_FamEvent(_FamKind.ping, DateTime(2026), '2'));
    await d.stop();
    // A throwing handler neither blocks other handlers for the same event
    // nor subsequent events.
    expect(good.tags, ['1', '2']);
  });

  test('stop drains queued events before closing', () async {
    final d = AsyncDispatcher()..start();
    final r = _Recorder();
    d.registerFamily<_FamKind>(_FamKind, r);
    for (var i = 0; i < 50; i++) {
      d.dispatch(_FamEvent(_FamKind.ping, DateTime(2026), '$i'));
    }
    await d.stop();
    expect(r.tags.length, 50);
    expect(r.tags.first, '0');
    expect(r.tags.last, '49');
    expect(d.queued, 0);
  });

  test('handled counts exposed per family kind', () async {
    final d = AsyncDispatcher()..start();
    final r = _Recorder();
    d.registerFamily<_FamKind>(_FamKind, r);
    d.dispatch(_FamEvent(_FamKind.ping, DateTime(2026), 'a'));
    d.dispatch(_FamEvent(_FamKind.pong, DateTime(2026), 'b'));
    await d.stop();
    expect(d.handledCounts['_FamKind.ping'], 1);
    expect(d.handledCounts['_FamKind.pong'], 1);
  });
}
