import 'dart:async';

import 'package:ai_message_core/ai_message_core.dart';

import '../io/filesystem.dart';
import '../../utils/logging/logger.dart';
import 'acp_chat_transcript_replay.dart';

/// Append-free snapshot of one ACP chat session's folded messages.
///
/// Writes are coalesced: only the newest queued snapshot is encoded, so a burst
/// of tool-call updates rewrites the transcript once instead of once per
/// update. Each call still resolves only after a write that includes its state
/// (or newer) lands, so `loadMessages` never observes an older snapshot.
class AcpChatTranscriptWriter {
  AcpChatTranscriptWriter({required Filesystem fs, required this.path})
    : _fs = fs;

  final Filesystem _fs;
  final String path;

  Future<void> _pending = Future<void>.value();

  /// Newest snapshot waiting to be written; supersedes earlier queued ones.
  List<AiMessage>? _queued;
  Completer<void>? _queuedDone;
  bool _draining = false;

  Future<List<AiMessage>> loadMessages() async {
    await _pending;
    final raw = await _fs.readString(path);
    final loaded = decodeAcpChatTranscript(raw);
    if ((raw != null && raw.trim().isNotEmpty) && loaded.isEmpty) {
      appLogger.w('[acp-transcript] ignored non-v1 snapshot path=$path');
    }
    return loaded;
  }

  Future<void> saveMessages(List<AiMessage> messages) {
    _queued = messages;
    final done = _queuedDone ??= Completer<void>();
    if (!_draining) {
      _draining = true;
      _pending = _drain().catchError((Object _) {});
    }
    return done.future;
  }

  Future<void> _drain() async {
    try {
      while (_queued != null) {
        final snapshot = _queued!;
        final done = _queuedDone!;
        _queued = null;
        _queuedDone = null;
        try {
          await _fs.atomicWrite(path, encodeAcpChatTranscript(snapshot));
        } on Object catch (error, stackTrace) {
          done.completeError(error, stackTrace);
          final queuedDone = _queuedDone;
          _queued = null;
          _queuedDone = null;
          queuedDone?.completeError(error, stackTrace);
          rethrow;
        }
        done.complete();
      }
    } finally {
      _draining = false;
    }
  }
}
