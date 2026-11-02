import 'dart:async';
import 'dart:isolate';

import 'package:ai_message_core/ai_message_core.dart';

import 'session_transcript_doc.dart';

/// Parses a transcript and projects it into a [SessionTranscriptDoc] on a
/// background isolate.
///
/// Decoding a large JSONL transcript is the expensive half of warming the
/// session content index (the projection itself is cheap). The worker keeps the
/// parse off the UI isolate and ships back only the projected searchable text —
/// never the message graph.
///
/// One long-lived worker serves a [WorkspaceSessionContentIndex], so warming
/// hundreds of seats pays the isolate spawn once. CLI transcript adapters are
/// stateless `const` objects; when one cannot cross the isolate boundary (a fake
/// capturing a closure in tests, say) [build] throws and the caller falls back
/// to parsing locally.
class IsolatedTranscriptDoc {
  Isolate? _isolate;
  ReceivePort? _reply;
  SendPort? _control;
  Future<void>? _starting;
  Completer<void>? _ready;
  int _nextId = 0;
  final Map<int, Completer<SessionTranscriptDoc>> _pending = {};

  /// How long a single parse may take before the worker is considered wedged.
  /// Generous: a huge transcript legitimately needs seconds.
  static const parseTimeout = Duration(seconds: 30);

  /// Parses [bundle] with [adapter] on the worker and returns the projected
  /// doc. Throws when the worker cannot run the parse (caller falls back).
  Future<SessionTranscriptDoc> build(
    AiTranscriptAdapter adapter,
    AiTranscriptBundle bundle,
  ) async {
    await _ensureStarted();
    final control = _control;
    if (control == null) {
      throw StateError('transcript worker was released');
    }
    final id = ++_nextId;
    final completer = Completer<SessionTranscriptDoc>();
    _pending[id] = completer;
    try {
      control.send(_TranscriptBuildRequest(id, adapter, bundle));
    } on Object {
      _pending.remove(id);
      rethrow;
    }
    try {
      return await completer.future.timeout(parseTimeout);
    } on TimeoutException {
      _pending.remove(id);
      // The worker is wedged (or the message was dropped): recycle it so the
      // next warm starts clean, and let the caller parse locally.
      dispose();
      rethrow;
    }
  }

  /// Tears the worker down. In-flight parses fail rather than hang.
  void dispose() {
    _control?.send(const _TranscriptCloseRequest());
    _control = null;
    _releaseWorker();
    for (final completer in _pending.values) {
      if (!completer.isCompleted) {
        completer.completeError(StateError('transcript worker disposed'));
      }
    }
    _pending.clear();
  }

  Future<void> _ensureStarted() {
    final started = _starting;
    if (started != null) return started;
    final future = _startWorker();
    _starting = future;
    return future;
  }

  Future<void> _startWorker() async {
    final reply = ReceivePort();
    final ready = Completer<void>();
    _reply = reply;
    _ready = ready;
    reply.listen(_onMessage);
    try {
      _isolate = await Isolate.spawn(_transcriptWorkerMain, reply.sendPort);
      await ready.future;
      if (_control == null) {
        _isolate?.kill(priority: Isolate.immediate);
        _isolate = null;
        throw StateError('transcript worker was released');
      }
    } on Object {
      _releaseWorker();
      _starting = null;
      rethrow;
    }
  }

  void _onMessage(Object? message) {
    switch (message) {
      case _TranscriptWorkerReady(:final control):
        _control = control;
        final ready = _ready;
        if (ready != null && !ready.isCompleted) ready.complete();
      case _TranscriptBuildReply(:final id, :final doc, :final error):
        final completer = _pending.remove(id);
        if (completer == null || completer.isCompleted) return;
        if (error != null) {
          completer.completeError(StateError(error));
          return;
        }
        completer.complete(doc!);
    }
  }

  void _releaseWorker() {
    _reply?.close();
    _reply = null;
    _isolate = null;
    _starting = null;
    final ready = _ready;
    _ready = null;
    if (ready != null && !ready.isCompleted) ready.complete();
  }
}

class _TranscriptWorkerReady {
  const _TranscriptWorkerReady(this.control);

  final SendPort control;
}

class _TranscriptBuildRequest {
  const _TranscriptBuildRequest(this.id, this.adapter, this.bundle);

  final int id;
  final AiTranscriptAdapter adapter;
  final AiTranscriptBundle bundle;
}

class _TranscriptBuildReply {
  const _TranscriptBuildReply(this.id, this.doc, this.error);

  final int id;

  /// Null when [error] is set.
  final SessionTranscriptDoc? doc;
  final String? error;
}

class _TranscriptCloseRequest {
  const _TranscriptCloseRequest();
}

Future<void> _transcriptWorkerMain(SendPort reply) async {
  final control = ReceivePort();
  reply.send(_TranscriptWorkerReady(control.sendPort));
  try {
    await for (final message in control) {
      switch (message) {
        case _TranscriptBuildRequest(:final id, :final adapter, :final bundle):
          try {
            final messages = await adapter.parse(bundle);
            reply.send(
              _TranscriptBuildReply(id, buildTranscriptDoc(messages), null),
            );
          } on Object catch (error) {
            reply.send(_TranscriptBuildReply(id, null, '$error'));
          }
        case _TranscriptCloseRequest():
          return;
      }
    }
  } finally {
    control.close();
  }
}
