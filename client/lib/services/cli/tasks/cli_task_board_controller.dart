import 'dart:async';

import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter/foundation.dart';

import 'cli_task_board.dart';

/// Memoizing presenter: re-derives [board] from the FULL loaded transcript
/// (not the thread's visible window) only when its content actually changes.
///
/// The seat holds the full transcript in [AiHistorySeat.loadedMessages]; the
/// thread runtime only publishes a paginated slice (`kSessionHistoryInitialTurns`
/// turns). Deriving from the slice would drop TaskCreate calls that fell
/// outside the window and turn the later TaskUpdate calls into empty
/// placeholders — so the board reads the full list and uses the runtime only
/// as a change signal.
class CliTaskBoardController extends ChangeNotifier {
  CliTaskBoardController({
    required AiThreadRuntime runtime,
    required List<AiMessage> Function() loadedMessages,
  }) : _loadedMessages = loadedMessages {
    _last = loadedMessages();
    _board = reduceCliTaskBoard(_last);
    _sub = runtime.changes.listen((_) => _onChanges());
  }

  final List<AiMessage> Function() _loadedMessages;
  late List<AiMessage> _last;
  late CliTaskBoard _board;
  StreamSubscription<void>? _sub;

  CliTaskBoard get board => _board;

  void _onChanges() {
    final messages = _loadedMessages();
    if (_sameInstancesInOrder(messages, _last)) return;
    _last = messages;
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
