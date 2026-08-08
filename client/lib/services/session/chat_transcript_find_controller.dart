import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter/foundation.dart';
import 'workspace_session_content_index.dart';

/// Result-cap for the find results list.
const int kChatFindMaxResults = 50;

/// One match in the transcript: the message it lives in (index into the full
/// loaded message list + its id) and a snippet around the first occurrence.
class TranscriptHit {
  const TranscriptHit({
    required this.messageIndex,
    required this.messageId,
    required this.snippet,
  });

  final int messageIndex;
  final String messageId;
  final String snippet;
}

/// Full-transcript find for one chat seat. Builds a [SessionTranscriptDoc]
/// from the seat's **in-memory** `loadedMessages` (indices align 1:1), scans
/// every case-insensitive occurrence, and tracks a current match (n/N).
///
/// The doc is cached and rebuilt only when the message-list instance changes,
/// so repeated keystrokes scan text without re-projecting messages.
class ChatTranscriptFindController extends ChangeNotifier {
  ChatTranscriptFindController({required this.messagesProvider});

  final List<AiMessage> Function() messagesProvider;

  String _query = '';
  List<TranscriptHit> _hits = const [];
  int _currentIndex = -1;

  SessionTranscriptDoc? _doc;
  List<AiMessage>? _docMessages;

  /// The message-list instance whose hits were last computed, so a re-search of
  /// the same query text still re-scans when the transcript grew (new instance).
  List<AiMessage>? _scannedMessages;

  String get query => _query;
  List<TranscriptHit> get hits => _hits;
  int get currentIndex => _hits.isEmpty ? -1 : _currentIndex;
  bool get hasQuery => _query.trim().isNotEmpty;
  TranscriptHit? get current =>
      _hits.isEmpty || _currentIndex < 0 ? null : _hits[_currentIndex];

  void search(String value) {
    final query = value.trim();
    final messages = messagesProvider();
    // Re-scan even for the same query text when the transcript's message-list
    // instance changed (live refresh / loadOlder), so hits don't go stale.
    if (query == _query && identical(_scannedMessages, messages)) return;
    _query = query;
    if (query.isEmpty) {
      _hits = const [];
      _currentIndex = -1;
      _scannedMessages = null;
      notifyListeners();
      return;
    }
    final doc = _docFor(messages);
    _hits = _scan(query, doc, messages);
    _scannedMessages = messages;
    _currentIndex = _hits.isEmpty ? -1 : 0;
    notifyListeners();
  }

  void next() {
    if (_hits.isEmpty) return;
    _currentIndex = (_currentIndex + 1) % _hits.length;
    notifyListeners();
  }

  void previous() {
    if (_hits.isEmpty) return;
    _currentIndex = (_currentIndex - 1 + _hits.length) % _hits.length;
    notifyListeners();
  }

  void clear() => search('');

  SessionTranscriptDoc _docFor(List<AiMessage> messages) {
    if (identical(_docMessages, messages)) {
      return _doc ?? buildTranscriptDoc(messages);
    }
    _doc = buildTranscriptDoc(messages);
    _docMessages = messages;
    return _doc!;
  }

  static List<TranscriptHit> _scan(
    String query,
    SessionTranscriptDoc doc,
    List<AiMessage> messages,
  ) {
    final pattern = RegExp(RegExp.escape(query), caseSensitive: false);
    final hits = <TranscriptHit>[];
    for (final match in pattern.allMatches(doc.text)) {
      if (hits.length >= kChatFindMaxResults) break;
      final index = match.start;
      // Use the match's real extent, not query.length: case-folded matches can
      // differ in code-unit length, and the downstream highlight slices the
      // snippet by this bound.
      final matchLength = match.end - match.start;
      final messageIndex = WorkspaceSessionContentIndex.messageIndexAt(
        doc.messageStarts,
        index,
      );
      if (messageIndex < 0 || messageIndex >= messages.length) continue;
      hits.add(
        TranscriptHit(
          messageIndex: messageIndex,
          messageId: messages[messageIndex].id,
          snippet: WorkspaceSessionContentIndex.snippetAround(
            doc.text,
            index,
            matchLength,
          ),
        ),
      );
    }
    return hits;
  }
}
