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
  bool _caseSensitive = false;
  bool _wholeWord = false;
  bool _regex = false;
  List<TranscriptHit> _hits = const [];
  int _currentIndex = -1;

  SessionTranscriptDoc? _doc;
  List<AiMessage>? _docMessages;

  /// The message-list instance whose hits were last computed, so a re-search of
  /// the same query text still re-scans when the transcript grew (new instance).
  List<AiMessage>? _scannedMessages;

  String get query => _query;
  bool get caseSensitive => _caseSensitive;
  bool get wholeWord => _wholeWord;
  bool get regex => _regex;
  List<TranscriptHit> get hits => _hits;
  int get currentIndex => _hits.isEmpty ? -1 : _currentIndex;
  bool get hasQuery => _query.trim().isNotEmpty;
  TranscriptHit? get current =>
      _hits.isEmpty || _currentIndex < 0 ? null : _hits[_currentIndex];

  void toggleCaseSensitive() {
    _caseSensitive = !_caseSensitive;
    _rescan();
  }

  void toggleWholeWord() {
    _wholeWord = !_wholeWord;
    _rescan();
  }

  void toggleRegex() {
    _regex = !_regex;
    _rescan();
  }

  void search(String value) {
    final query = value.trim();
    final messages = messagesProvider();
    // Re-scan even for the same query text when the transcript's message-list
    // instance changed (live refresh / loadOlder), so hits don't go stale.
    if (query == _query && identical(_scannedMessages, messages)) return;
    _query = query;
    _rescan(messages: messages);
  }

  /// Re-runs the scan for the current query (e.g. after toggling an option),
  /// always re-scanning regardless of the message-list instance.
  void _rescan({List<AiMessage>? messages}) {
    final query = _query.trim();
    final List<AiMessage> msgs = messages ?? messagesProvider();
    if (query.isEmpty) {
      _hits = const [];
      _currentIndex = -1;
      _scannedMessages = null;
      notifyListeners();
      return;
    }
    final doc = _docFor(msgs);
    _hits = _scan(
      query,
      doc,
      msgs,
      caseSensitive: _caseSensitive,
      wholeWord: _wholeWord,
      regex: _regex,
    );
    _scannedMessages = msgs;
    _currentIndex = _hits.isEmpty ? -1 : 0;
    notifyListeners();
  }

  /// Sets the current match index (e.g. when the user taps a specific result
  /// row). No-op when out of range or there are no hits.
  void select(int index) {
    if (_hits.isEmpty) return;
    if (index < 0 || index >= _hits.length) return;
    _currentIndex = index;
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
    List<AiMessage> messages, {
    bool caseSensitive = false,
    bool wholeWord = false,
    bool regex = false,
  }) {
    final String source = regex ? query : RegExp.escape(query);
    final RegExp pattern;
    try {
      pattern = RegExp(
        wholeWord ? '(?<![\\w])(?:$source)(?![\\w])' : source,
        caseSensitive: caseSensitive,
      );
    } on FormatException {
      // Invalid regex: treat as no matches rather than crashing the search.
      return const [];
    }
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
