import 'dart:async';

import 'message.dart';

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

  void setMessages(List<AiMessage> messages) {
    _messages = List.of(messages);
    _status = messages.isEmpty ? AiThreadStatus.empty : AiThreadStatus.idle;
    _errorMessage = null;
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

  void _notify() {
    if (!_changes.isClosed) {
      _changes.add(null);
    }
  }
}
