import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/event/async_dispatcher.dart';
import 'package:teampilot/services/event/dispatcher.dart';
import 'package:teampilot/utils/logging/logger_utils.dart';

enum _FamKind { ping, pong }

enum _OtherKind { ping }

class _FamEvent implements DispatcherEvent<_FamKind> {
  const _FamEvent(this.eventKind, this.timestamp, [this.tag = '']);

  @override
  final _FamKind eventKind;
  @override
  final DateTime timestamp;
  final String tag;
}

class _OtherEvent implements DispatcherEvent<_OtherKind> {
  const _OtherEvent(this.eventKind, this.timestamp);

  @override
  final _OtherKind eventKind;
  @override
  final DateTime timestamp;
}

class _Recorder implements EventHandler<_FamEvent> {
  final tags = <String>[];

  @override
  void handle(_FamEvent event) => tags.add(event.tag);
}

class _ThrowingHandler implements EventHandler<_FamEvent> {
  _ThrowingHandler([Object? error]) : error = error ?? StateError('boom');

  final Object error;

  @override
  void handle(_FamEvent event) => throw error;
}

/// Captures `e(...)` calls so tests can assert the recordError flag without
/// touching the singleton AppLogger (whose default path would surface global
/// error toasts / reports for classified errors).
class _SpyLogger implements AppLogger {
  final errors = <({Object? error, bool recordError})>[];

  @override
  void e(
    String message, {
    Object? error,
    StackTrace? stackTrace,
    bool recordError = true,
  }) {
    errors.add((error: error, recordError: recordError));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
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

  test('handler exception is logged without recording a global error', () async {
    final spy = _SpyLogger();
    final d = AsyncDispatcher(logger: spy)..start();
    final good = _Recorder();
    // A network-classified error would, via the default recordError: true,
    // surface a global error toast (AppErrorUtils.showDecisionMessage).
    d.registerFamily<_FamKind>(
      _FamKind,
      _ThrowingHandler(const SocketException('Connection refused')),
    );
    d.registerFamily<_FamKind>(_FamKind, good);
    d.dispatch(_FamEvent(_FamKind.ping, DateTime(2026), '1'));
    await d.stop();
    expect(good.tags, ['1']); // isolation still holds
    expect(spy.errors, hasLength(1));
    // The side-effecting global-error path must NOT be triggered.
    expect(spy.errors.single.recordError, isFalse);
    expect(spy.errors.single.error, isA<SocketException>());
  });

  test('start during stop drain does not orphan the consume loop', () async {
    final d = AsyncDispatcher()..start();
    final r = _Recorder();
    d.registerFamily<_FamKind>(_FamKind, r);
    d.dispatch(_FamEvent(_FamKind.ping, DateTime(2026), '1'));
    // stop() begins draining; before the old loop's wake microtask runs,
    // start() spawns a newer-generation loop.
    final draining = d.stop();
    await d.start();
    await draining;
    // New generation is live: fresh events are delivered.
    d.dispatch(_FamEvent(_FamKind.ping, DateTime(2026), '2'));
    await d.stop();
    expect(r.tags, ['1', '2']);
    expect(d.queued, 0); // no orphaned loop holding/leaking queued events
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
