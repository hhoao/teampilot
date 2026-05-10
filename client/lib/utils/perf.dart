import 'dart:developer' as developer;

/// Wrap a synchronous call with timeline events and debug logging.
/// Returns the result of [fn] after measuring its wall-clock duration.
T trackSync<T>(String label, T Function() fn) {
  developer.Timeline.startSync(label);
  final sw = Stopwatch()..start();
  try {
    return fn();
  } finally {
    sw.stop();
    developer.Timeline.finishSync();
    if (sw.elapsedMilliseconds > 8) {
      // ignore: avoid_print
      print('[perf] $label: ${sw.elapsedMilliseconds}ms');
    }
  }
}

/// Wrap an async call with timeline events and debug logging.
Future<T> trackAsync<T>(String label, Future<T> Function() fn) async {
  developer.Timeline.startSync(label);
  final sw = Stopwatch()..start();
  try {
    return await fn();
  } finally {
    sw.stop();
    developer.Timeline.finishSync();
    if (sw.elapsedMilliseconds > 16) {
      // ignore: avoid_print
      print('[perf] $label: ${sw.elapsedMilliseconds}ms');
    }
  }
}

class PerfMark {
  PerfMark(this.label) : _start = Stopwatch()..start();

  final String label;
  final Stopwatch _start;

  void stop() {
    _start.stop();
    if (_start.elapsedMilliseconds > 8) {
      // ignore: avoid_print
      print('[perf] $label: ${_start.elapsedMilliseconds}ms');
    }
  }
}
