import 'dart:async';

import 'message.dart';
import 'message_content_identity.dart';

enum AiThreadStatus { idle, loading, empty, error }

abstract class AiThreadRuntime {
  List<AiMessage> get messages;
  AiThreadStatus get status;
  String? get errorMessage;
  Stream<void> get changes;
}

class ExternalStoreAiThreadRuntime implements AiThreadRuntime {
  ExternalStoreAiThreadRuntime()
      : _changes = StreamController<void>.broadcast(sync: true);

  final StreamController<void> _changes;

  List<AiMessage> _messages = const [];
  AiThreadStatus _status = AiThreadStatus.empty;
  String? _errorMessage;

  @override
  List<AiMessage> get messages => List.unmodifiable(_messages);

  @override
  AiThreadStatus get status => _status;

  @override
  String? get errorMessage => _errorMessage;

  @override
  Stream<void> get changes => _changes.stream;

  void setLoading() {
    _messages = const [];
    _status = AiThreadStatus.loading;
    _errorMessage = null;
    _notify();
  }

  /// Replaces the message list.
  ///
  /// Unchanged messages (same [messageContentIdentity]) keep their prior
  /// instances. When membership, order, and content are all unchanged, skips
  /// [changes] notification so hosts do not fan out a full-thread rebuild.
  void setMessages(List<AiMessage> messages) {
    final merged = _mergeReusingUnchanged(messages);
    final nextStatus =
        merged.isEmpty ? AiThreadStatus.empty : AiThreadStatus.idle;
    final contentUnchanged = _sameInstancesInOrder(_messages, merged);
    final statusUnchanged =
        _status == nextStatus && _errorMessage == null;
    _messages = merged;
    _status = nextStatus;
    _errorMessage = null;
    if (contentUnchanged && statusUnchanged) return;
    _notify();
  }

  void setEmpty() {
    _messages = const [];
    _status = AiThreadStatus.empty;
    _errorMessage = null;
    _notify();
  }

  void setError(String message) {
    _messages = const [];
    _status = AiThreadStatus.error;
    _errorMessage = message;
    _notify();
  }

  void close() {
    _changes.close();
  }

  List<AiMessage> _mergeReusingUnchanged(List<AiMessage> incoming) {
    if (incoming.isEmpty) return const [];
    if (_messages.isEmpty) return List<AiMessage>.of(incoming);

    final previousById = <String, AiMessage>{
      for (final m in _messages) m.id: m,
    };

    // Identity strings build every part's payload (text, reasoning, tool
    // results) — expensive for messages with large results. Only compute them
    // for messages whose instance changed; identical instances reuse directly.
    final merged = <AiMessage>[];
    for (final m in incoming) {
      final prev = previousById[m.id];
      if (identical(prev, m)) {
        merged.add(m);
        continue;
      }
      if (prev != null &&
          messageContentIdentity(prev) == messageContentIdentity(m)) {
        merged.add(prev);
        continue;
      }
      merged.add(m);
    }
    return merged;
  }

  static bool _sameInstancesInOrder(List<AiMessage> a, List<AiMessage> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!identical(a[i], b[i])) return false;
    }
    return true;
  }

  void _notify() {
    if (!_changes.isClosed) {
      _changes.add(null);
    }
  }
}
