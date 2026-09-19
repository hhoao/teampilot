import '../services/catalog/workspace_catalog.dart';
import 'chat_state.dart';

/// Read access to the app-level chat state plus the single emit entry point.
///
/// Launch collaborators that only need to *look at* state and check liveness
/// take this port instead of the full `SessionLaunchHost`.
abstract interface class ChatStatePort {
  ChatState get state;

  /// True once the owning cubit is closed; async launch steps re-check it after
  /// every await so a torn-down cubit is never written to.
  bool get isClosed;

  /// Current four-tuple snapshot of [state] (workspaces / sessions / visible*).
  /// Lets the session domain patch in-memory state without a full rescan.
  ChatDataSnapshot stateSnapshot();

  /// Single emit entry point (wraps the cubit's protected emit).
  void applyState(ChatState next);

  void refreshActiveWorkspaceTabs();

  PostFrameScheduler get postFrameScheduler;
}
