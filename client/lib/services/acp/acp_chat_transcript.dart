import 'dart:async';

import 'package:ai_message_core/ai_message_core.dart';

import '../io/filesystem.dart';
import '../../utils/logging/logger.dart';
import 'acp_chat_transcript_replay.dart';

/// Append-free snapshot of one ACP chat session's folded messages.
class AcpChatTranscriptWriter {
  AcpChatTranscriptWriter({required Filesystem fs, required this.path})
    : _fs = fs;

  final Filesystem _fs;
  final String path;

  Future<void> _pending = Future<void>.value();

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
    final next = _pending.then((_) async {
      await _fs.atomicWrite(path, encodeAcpChatTranscript(messages));
    });
    _pending = next.catchError((Object _) {});
    return next;
  }
}
