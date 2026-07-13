import 'dart:async';

import 'package:flutter/foundation.dart';

import 'process_run_executor.dart';

/// Thin mapper: session output events → scrollable text buffers for Run pages.
///
/// Keeps one [StringBuffer] per session id. Panels listen via [Listenable] /
/// [textFor] rather than owning a second output pipeline.
class RunTerminalBridge extends ChangeNotifier {
  RunTerminalBridge({Stream<ProcessRunOutput>? outputStream}) {
    if (outputStream != null) {
      _subscription = outputStream.listen(append);
    }
  }

  final Map<String, StringBuffer> _buffers = {};
  StreamSubscription<ProcessRunOutput>? _subscription;

  /// Full accumulated log text for [sessionId] (empty when none yet).
  String textFor(String sessionId) => _buffers[sessionId]?.toString() ?? '';

  /// Appends one output chunk and notifies listeners.
  void append(ProcessRunOutput output) {
    final buffer = _buffers.putIfAbsent(output.sessionId, StringBuffer.new);
    buffer.write(output.data);
    notifyListeners();
  }

  /// Replaces buffered text for [sessionId] (e.g. seed from session manager).
  void seed(String sessionId, String text) {
    if (text.isEmpty) {
      _buffers.remove(sessionId);
    } else {
      _buffers[sessionId] = StringBuffer(text);
    }
    notifyListeners();
  }

  /// Drops buffered text for a closed/dismissed session.
  void clear(String sessionId) {
    if (_buffers.remove(sessionId) != null) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    _subscription = null;
    _buffers.clear();
    super.dispose();
  }
}
