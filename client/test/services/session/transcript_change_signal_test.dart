import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/io/filesystem.dart';
import 'package:teampilot/services/session/transcript_change_signal.dart';

import '../../support/in_memory_filesystem.dart';

class _WatchableFs extends InMemoryFilesystem implements FsWatcher {
  final _controller = StreamController<FsChangeEvent>.broadcast();
  var closeCount = 0;
  var watchTreeCallCount = 0;
  String? lastWatchRoot;

  void emit(FsChangeType type, String path) =>
      _controller.add(FsChangeEvent(path: path, type: type));

  @override
  FsTreeWatch watchTree(String path) {
    watchTreeCallCount++;
    lastWatchRoot = path;
    return FsTreeWatch(
      events: _controller.stream,
      close: () async {
        closeCount++;
      },
    );
  }
}

void main() {
  group('TranscriptChangeSignal', () {
    test('FsWatcher: watchTree event notifies after debounce', () {
      fakeAsync((async) {
        final fs = _WatchableFs();
        var notifies = 0;
        final signal = TranscriptChangeSignal(
          fs: fs,
          watchRoot: () => '/proj',
          cacheTokenPaths: () => const ['/proj/a.jsonl'],
          onChanged: () => notifies++,
          watchDebounce: const Duration(milliseconds: 150),
        );

        unawaited(signal.start());
        async.flushMicrotasks();
        expect(fs.watchTreeCallCount, 1);
        expect(fs.lastWatchRoot, '/proj');

        fs.emit(FsChangeType.modified, '/proj/a.jsonl');
        fs.emit(FsChangeType.modified, '/proj/a.jsonl');
        async.elapse(const Duration(milliseconds: 149));
        async.flushMicrotasks();
        expect(notifies, 0);

        async.elapse(const Duration(milliseconds: 1));
        async.flushMicrotasks();
        expect(notifies, 1);

        unawaited(signal.stop());
        async.flushMicrotasks();
      });
    });

    test('non-FsWatcher: polls cache tokens and notifies on change', () {
      fakeAsync((async) {
        final fs = InMemoryFilesystem();
        var notifies = 0;
        var paths = <String>['/proj/a.jsonl'];
        final signal = TranscriptChangeSignal(
          fs: fs,
          watchRoot: () => null,
          cacheTokenPaths: () => paths,
          onChanged: () => notifies++,
          pollInterval: const Duration(milliseconds: 750),
        );

        unawaited(signal.start());
        async.flushMicrotasks();

        // Missing file → empty token → no notify.
        async.elapse(const Duration(milliseconds: 750));
        async.flushMicrotasks();
        expect(notifies, 0);

        unawaited(fs.writeString('/proj/a.jsonl', 'hello'));
        async.flushMicrotasks();

        async.elapse(const Duration(milliseconds: 750));
        async.flushMicrotasks();
        expect(notifies, 1);

        // Unchanged content → no second notify.
        async.elapse(const Duration(milliseconds: 750));
        async.flushMicrotasks();
        expect(notifies, 1);

        unawaited(fs.writeString('/proj/a.jsonl', 'hello!'));
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 750));
        async.flushMicrotasks();
        expect(notifies, 2);

        unawaited(signal.stop());
        async.flushMicrotasks();
      });
    });

    test('stop cancels watch and debounce; no further notifies', () {
      fakeAsync((async) {
        final fs = _WatchableFs();
        var notifies = 0;
        final signal = TranscriptChangeSignal(
          fs: fs,
          watchRoot: () => '/proj',
          cacheTokenPaths: () => const [],
          onChanged: () => notifies++,
          watchDebounce: const Duration(milliseconds: 150),
        );

        unawaited(signal.start());
        async.flushMicrotasks();
        expect(fs.watchTreeCallCount, 1);

        fs.emit(FsChangeType.created, '/proj/a.jsonl');
        unawaited(signal.stop());
        async.flushMicrotasks();
        expect(fs.closeCount, 1);

        async.elapse(const Duration(milliseconds: 200));
        async.flushMicrotasks();
        expect(notifies, 0);

        fs.emit(FsChangeType.modified, '/proj/a.jsonl');
        async.elapse(const Duration(milliseconds: 200));
        async.flushMicrotasks();
        expect(notifies, 0);
      });
    });

    test('stop cancels poll timer; no further notifies', () {
      fakeAsync((async) {
        final fs = InMemoryFilesystem();
        unawaited(fs.writeString('/proj/a.jsonl', 'v1'));
        async.flushMicrotasks();

        var notifies = 0;
        final signal = TranscriptChangeSignal(
          fs: fs,
          watchRoot: () => null,
          cacheTokenPaths: () => const ['/proj/a.jsonl'],
          onChanged: () => notifies++,
          pollInterval: const Duration(milliseconds: 750),
        );

        unawaited(signal.start());
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 750));
        async.flushMicrotasks();
        expect(notifies, 1);

        unawaited(signal.stop());
        async.flushMicrotasks();

        unawaited(fs.writeString('/proj/a.jsonl', 'v2'));
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 3000));
        async.flushMicrotasks();
        expect(notifies, 1);
      });
    });

    test('empty paths keep polling; notifies on first non-empty token', () {
      fakeAsync((async) {
        final fs = InMemoryFilesystem();
        var notifies = 0;
        var paths = <String>[];
        final signal = TranscriptChangeSignal(
          fs: fs,
          watchRoot: () => null,
          cacheTokenPaths: () => paths,
          onChanged: () => notifies++,
          pollInterval: const Duration(milliseconds: 750),
        );

        unawaited(signal.start());
        async.flushMicrotasks();

        async.elapse(const Duration(milliseconds: 750));
        async.flushMicrotasks();
        expect(notifies, 0);

        // Late locate populates a missing path — still empty token.
        paths = ['/proj/a.jsonl'];
        async.elapse(const Duration(milliseconds: 750));
        async.flushMicrotasks();
        expect(notifies, 0);

        unawaited(fs.writeString('/proj/a.jsonl', 'hi'));
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 750));
        async.flushMicrotasks();
        expect(notifies, 1);

        unawaited(signal.stop());
        async.flushMicrotasks();
      });
    });

    test('FsWatcher with null watchRoot falls back to poll', () {
      fakeAsync((async) {
        final fs = _WatchableFs();
        unawaited(fs.writeString('/proj/a.jsonl', 'a'));
        async.flushMicrotasks();

        var notifies = 0;
        String? root;
        final signal = TranscriptChangeSignal(
          fs: fs,
          watchRoot: () => root,
          cacheTokenPaths: () => const ['/proj/a.jsonl'],
          onChanged: () => notifies++,
          pollInterval: const Duration(milliseconds: 750),
          watchDebounce: const Duration(milliseconds: 150),
        );

        unawaited(signal.start());
        async.flushMicrotasks();
        expect(fs.watchTreeCallCount, 0);

        async.elapse(const Duration(milliseconds: 750));
        async.flushMicrotasks();
        expect(notifies, 1);

        // Late root enables watch upgrade.
        root = '/proj';
        async.elapse(const Duration(milliseconds: 750));
        async.flushMicrotasks();
        expect(fs.watchTreeCallCount, 1);

        fs.emit(FsChangeType.modified, '/proj/a.jsonl');
        async.elapse(const Duration(milliseconds: 150));
        async.flushMicrotasks();
        expect(notifies, 2);

        unawaited(signal.stop());
        async.flushMicrotasks();
      });
    });

    test('poll resumes after cacheTokenPaths throws once', () {
      fakeAsync((async) {
        final fs = InMemoryFilesystem();
        unawaited(fs.writeString('/proj/a.jsonl', 'data'));
        async.flushMicrotasks();

        var notifies = 0;
        var pathCalls = 0;
        final signal = TranscriptChangeSignal(
          fs: fs,
          watchRoot: () => null,
          cacheTokenPaths: () {
            pathCalls++;
            if (pathCalls == 1) throw StateError('transient');
            return const ['/proj/a.jsonl'];
          },
          onChanged: () => notifies++,
          pollInterval: const Duration(milliseconds: 750),
        );

        unawaited(signal.start());
        async.flushMicrotasks();
        expect(notifies, 0);

        // First tick throws; the next periodic tick should recover.
        async.elapse(const Duration(milliseconds: 750));
        async.flushMicrotasks();
        expect(notifies, 1);

        unawaited(signal.stop());
        async.flushMicrotasks();
      });
    });
  });
}
