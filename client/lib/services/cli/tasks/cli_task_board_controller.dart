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
    final skipReduce = _sameTaskParts(messages, _last);
    _last = messages;
    if (skipReduce) return;
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

  /// Last-bubble live refresh often replaces the assistant message (Write,
  /// Shell, …) while TaskCreate / TaskUpdate / TodoWrite parts stay the
  /// same instances. Re-reducing the whole transcript on those ticks is
  /// wasted work and notifies History for no task-board change.
  static bool _sameTaskParts(List<AiMessage> a, List<AiMessage> b) {
    final pa = _collectTaskParts(a);
    final pb = _collectTaskParts(b);
    if (pa.length != pb.length) return false;
    for (var i = 0; i < pa.length; i++) {
      if (!identical(pa[i], pb[i])) return false;
    }
    return true;
  }

  static List<AiToolCallPart> _collectTaskParts(List<AiMessage> messages) {
    final parts = <AiToolCallPart>[];
    for (final message in messages) {
      for (final part in message.parts) {
        if (part is! AiToolCallPart) continue;
        switch (part.toolName.toLowerCase()) {
          case 'taskcreate':
          case 'taskupdate':
          case 'todowrite':
            parts.add(part);
        }
      }
    }
    return parts;
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
