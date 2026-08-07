import 'dart:async';

import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter/foundation.dart';

import 'cli_task_board.dart';

/// Memoizing presenter: re-derives [board] only when the runtime's message
/// list content actually changes.
///
/// The runtime reuses unchanged message instances and only notifies when
/// content changed, so an instance-identity comparison is a correct (and
/// cheap) change detector for the derivation.
class CliTaskBoardController extends ChangeNotifier {
  CliTaskBoardController(AiThreadRuntime runtime) {
    _runtime = runtime;
    _lastMessages = runtime.messages;
    _board = reduceCliTaskBoard(_lastMessages);
    _sub = runtime.changes.listen((_) => _onChanges());
  }

  late final AiThreadRuntime _runtime;
  late List<AiMessage> _lastMessages;
  late CliTaskBoard _board;
  StreamSubscription<void>? _sub;

  CliTaskBoard get board => _board;

  void _onChanges() {
    final messages = _runtime.messages;
    if (_sameInstancesInOrder(messages, _lastMessages)) return;
    _lastMessages = messages;
    _board = reduceCliTaskBoard(messages);
    notifyListeners();
  }

  static bool _sameInstancesInOrder(List<AiMessage> a, List<AiMessage> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!identical(a[i], b[i])) return false;
    }
    return true;
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
