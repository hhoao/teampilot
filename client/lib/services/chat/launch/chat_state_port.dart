import '../../catalog/chat_data_snapshot.dart';
import 'shell_launch_typedefs.dart';

export '../../catalog/chat_data_snapshot.dart' show ChatDataSnapshot;

/// Read access to the app-level chat snapshot plus liveness.
///
/// Launch collaborators that only need to *look at* workspaces/sessions
/// take this port instead of the full `SessionLaunchHost`. Cubit `ChatState`
/// stays in `cubits/`; launch reads the four-tuple via [stateSnapshot].
abstract interface class ChatStatePort {
  /// True once the owning cubit is closed; async launch steps re-check it after
  /// every await so a torn-down cubit is never written to.
  bool get isClosed;

  /// Current four-tuple snapshot (workspaces / sessions / visible*).
  /// Lets the session domain patch in-memory state without a full rescan.
  ChatDataSnapshot stateSnapshot();

  void refreshActiveWorkspaceTabs();

  PostFrameScheduler get postFrameScheduler;
}
