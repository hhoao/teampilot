/// Handler invoked when a command id fires.
typedef CommandHandler = void Function();

/// Registry mapping command ids to their currently-mounted handler.
///
/// Features register a handler while their owning widget/cubit is mounted
/// and unregister on dispose. [invoke] is a silent no-op when no handler is
/// registered — callers rely on this so a matched shortcut is still marked
/// handled even while chrome is mounting.
class CommandBus {
  final Map<String, CommandHandler> _handlers = {};

  /// Registers [handler] for [id], replacing any previously registered
  /// handler for the same id.
  void register(String id, CommandHandler handler) {
    _handlers[id] = handler;
  }

  /// Removes the handler for [id].
  ///
  /// If [handler] is provided, only removes it when it is still the
  /// currently registered handler for [id] (avoids a stale unregister from
  /// a disposing widget clobbering a handler registered later).
  void unregister(String id, [CommandHandler? handler]) {
    if (handler != null && _handlers[id] != handler) {
      return;
    }
    _handlers.remove(id);
  }

  /// Invokes the handler registered for [id], if any. Never throws when no
  /// handler is registered.
  void invoke(String id) {
    _handlers[id]?.call();
  }
}
