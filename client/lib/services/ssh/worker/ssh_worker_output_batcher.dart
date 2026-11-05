import 'dart:async';
import 'dart:typed_data';

/// Coalesces worker-owned PTY output into bounded, ordered frames.
///
/// [timerFactory] keeps time deterministic in tests that need to advance a
/// fake clock without sleeping.
final class SshWorkerOutputBatcher {
  SshWorkerOutputBatcher({
    this.flushInterval = const Duration(milliseconds: 16),
    this.maxBytes = 64 * 1024,
    Timer Function(Duration, void Function())? timerFactory,
  }) : _timerFactory = timerFactory ?? Timer.new {
    if (flushInterval < Duration.zero) {
      throw ArgumentError.value(flushInterval, 'flushInterval');
    }
    if (maxBytes < 1) throw ArgumentError.value(maxBytes, 'maxBytes');
  }

  final Duration flushInterval;
  final int maxBytes;
  final Timer Function(Duration, void Function()) _timerFactory;
  final StreamController<Uint8List> _output = StreamController<Uint8List>(
    sync: true,
  );
  final BytesBuilder _pending = BytesBuilder(copy: false);
  Timer? _timer;
  var _closed = false;

  Stream<Uint8List> get output => _output.stream;

  void add(Uint8List bytes) {
    if (_closed || bytes.isEmpty) return;
    if (_pending.isEmpty && bytes.length <= maxBytes) {
      _pending.add(bytes);
      if (_pending.length == maxBytes) {
        _flush();
      } else {
        _scheduleFlush();
      }
      return;
    }
    var offset = 0;
    while (offset < bytes.length) {
      final remaining = maxBytes - _pending.length;
      final count = (bytes.length - offset) < remaining
          ? bytes.length - offset
          : remaining;
      _pending.add(bytes.sublist(offset, offset + count));
      offset += count;
      if (_pending.length == maxBytes) {
        _flush();
      } else {
        _scheduleFlush();
      }
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _timer?.cancel();
    _timer = null;
    _flush();
    await _output.close();
  }

  void _scheduleFlush() {
    if (_timer != null || _pending.isEmpty) return;
    _timer = _timerFactory(flushInterval, () {
      _timer = null;
      _flush();
    });
  }

  void _flush() {
    if (_pending.isEmpty) return;
    _timer?.cancel();
    _timer = null;
    _output.add(_pending.takeBytes());
  }
}
