import 'dart:convert';

import 'package:ai_message_core/ai_message_core.dart';

import 'acp_session.dart';

/// Folds one ACP session's JSONL transcript into chat bubbles.
///
/// Mirrors the live ACP chat mapping: consecutive text/thought
/// chunks coalesce, tool-call updates upsert, `stop` rows are not bubbles
/// (error copy is in the following `system` record), and handshake `auth`
/// system rows are skipped — they are live probes, not history.
List<AiMessage> replayAcpChatTranscript(String? jsonl) {
  if (jsonl == null || jsonl.isEmpty) return const [];
  final fold = _AcpChatTranscriptFold();
  for (final line in jsonl.split('\n')) {
    if (line.trim().isEmpty) continue;
    try {
      final decoded = jsonDecode(line);
      if (decoded is Map) {
        fold.apply(Map<String, Object?>.from(decoded));
      }
    } on FormatException {
      // Torn tail from a crash mid-append: skip.
    }
  }
  return fold.messages;
}

/// Appends in-memory bubbles (e.g. a landing prompt) after disk history.
List<AiMessage> mergeHydratedAcpMessages({
  required List<AiMessage> loaded,
  required List<AiMessage> live,
}) {
  if (loaded.isEmpty) return live;
  if (live.isEmpty) return loaded;
  final skipLiveFirst =
      _userText(loaded.last) != null &&
      _userText(loaded.last) == _userText(live.first);
  return [...loaded, ...live.skip(skipLiveFirst ? 1 : 0)];
}

String? _userText(AiMessage message) {
  if (message.role != AiRole.user) return null;
  return message.parts.whereType<AiTextPart>().map((p) => p.text).join();
}

class _AcpChatTranscriptFold {
  final List<AiMessage> messages = [];

  void apply(Map<String, Object?> entry) {
    switch (entry['type']) {
      case 'user':
        _addUser(entry);
      case 'chunk':
        _addChunk(entry);
      case 'tool_call':
        _applyToolCall(entry);
      case 'system':
        _addSystem(entry);
      case 'stop':
        break;
    }
  }

  void _addUser(Map<String, Object?> entry) {
    final text = entry['text'];
    if (text is! String || text.isEmpty) return;
    messages.add(
      AiMessage(
        id: _id('u', entry),
        role: AiRole.user,
        parts: [AiTextPart(text: text)],
        createdAt: _at(entry),
      ),
    );
  }

  void _addChunk(Map<String, Object?> entry) {
    final text = entry['text'];
    if (text is! String || text.isEmpty) return;
    final thought = entry['thought'] == true;
    _appendParts(
      [thought ? AiReasoningPart(text: text) : AiTextPart(text: text)],
      at: _at(entry),
      id: _id('a', entry),
    );
  }

  void _addSystem(Map<String, Object?> entry) {
    if (entry['kind'] == 'auth') return;
    // Previous-process death is not chat history. Closing a tab waits for
    // SIGTERM (exit 0) and used to record that as "unexpected exit".
    if (entry['kind'] == 'processExited') return;
    final message = entry['message'];
    if (message is! String || message.isEmpty) return;
    if (messages.isNotEmpty) {
      final tip = messages.last;
      if (tip.role == AiRole.system &&
          tip.parts.whereType<AiTextPart>().map((p) => p.text).join() ==
              message) {
        return;
      }
    }
    messages.add(
      AiMessage(
        id: _id('sys', entry),
        role: AiRole.system,
        parts: [AiTextPart(text: message)],
        createdAt: _at(entry),
      ),
    );
  }

  void _applyToolCall(Map<String, Object?> entry) {
    final toolCallId = entry['toolCallId'];
    if (toolCallId is! String || toolCallId.isEmpty) return;
    final title = entry['title'];
    final status = _mapToolStatus(
      entry['status'] is String ? entry['status'] as String : null,
    );
    final failed = entry['status'] == AcpToolCallStatus.failed.name;
    for (var i = messages.length - 1; i >= 0; i--) {
      final message = messages[i];
      if (message.role != AiRole.assistant) break;
      final parts = [...message.parts];
      for (var j = parts.length - 1; j >= 0; j--) {
        final part = parts[j];
        if (part is AiToolCallPart && part.toolCallId == toolCallId) {
          parts[j] = part.copyWith(
            toolName: title is String ? title : part.toolName,
            status: status ?? part.status,
            isError: failed || part.isError,
          );
          messages[i] = message.copyWith(parts: parts);
          return;
        }
      }
      if (i == messages.length - 1) {
        messages[i] = message.copyWith(
          parts: [
            ...parts,
            AiToolCallPart(
              toolCallId: toolCallId,
              toolName: title is String ? title : toolCallId,
              status: status ?? AiToolCallStatus.incomplete,
              isError: failed,
            ),
          ],
        );
        return;
      }
    }
    _appendParts(
      [
        AiToolCallPart(
          toolCallId: toolCallId,
          toolName: title is String ? title : toolCallId,
          status: status ?? AiToolCallStatus.incomplete,
          isError: failed,
        ),
      ],
      at: _at(entry),
      id: _id('a', entry),
    );
  }

  void _appendParts(
    List<AiMessagePart> incoming, {
    required DateTime? at,
    required String id,
  }) {
    if (messages.isNotEmpty && messages.last.role == AiRole.assistant) {
      final tip = messages.last;
      messages[messages.length - 1] = tip.copyWith(
        parts: _coalesceStreamingParts(tip.parts, incoming),
      );
      return;
    }
    messages.add(
      AiMessage(
        id: id,
        role: AiRole.assistant,
        parts: _coalesceStreamingParts(const [], incoming),
        createdAt: at,
      ),
    );
  }

  static List<AiMessagePart> _coalesceStreamingParts(
    List<AiMessagePart> existing,
    List<AiMessagePart> incoming,
  ) {
    final out = [...existing];
    for (final part in incoming) {
      if (out.isEmpty) {
        out.add(part);
        continue;
      }
      final merged = _mergeStreamParts(out.last, part);
      if (merged != null) {
        out[out.length - 1] = merged;
      } else {
        out.add(part);
      }
    }
    return out;
  }

  static AiMessagePart? _mergeStreamParts(AiMessagePart a, AiMessagePart b) {
    if (a is AiTextPart && b is AiTextPart) {
      return AiTextPart(text: '${a.text}${b.text}');
    }
    if (a is AiReasoningPart && b is AiReasoningPart) {
      return AiReasoningPart(text: '${a.text}${b.text}');
    }
    return null;
  }

  static AiToolCallStatus? _mapToolStatus(String? status) => switch (status) {
    null => null,
    'pending' => AiToolCallStatus.incomplete,
    'inProgress' => AiToolCallStatus.running,
    'completed' => AiToolCallStatus.complete,
    'failed' => AiToolCallStatus.complete,
    _ => null,
  };

  static String _id(String prefix, Map<String, Object?> entry) {
    final seq = entry['seq'];
    return 'acp-$prefix-${seq is int ? seq : 0}';
  }

  static DateTime? _at(Map<String, Object?> entry) {
    final at = entry['at'];
    if (at is! String || at.isEmpty) return null;
    return DateTime.tryParse(at);
  }
}
