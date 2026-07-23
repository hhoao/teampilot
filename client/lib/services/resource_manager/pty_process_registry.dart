/// In-memory map of Resource Manager binding keys to local PTY process ids.
///
/// Only local transports contribute pids; SSH stays unregistered (`null` pid).
/// Ownership of when to register/unregister lives in ResourceManagerCubit
/// (sync from bindings), not in TerminalLaunchController.
class PtyProcessRegistry {
  final Map<String, int> _byKey = {};

  /// Registers [pid] for [bindingKey]. A null [pid] is a no-op (does not clear).
  void register({required String bindingKey, required int? pid}) {
    if (pid == null) return;
    _byKey[bindingKey] = pid;
  }

  void unregister(String bindingKey) {
    _byKey.remove(bindingKey);
  }

  int? pidFor(String bindingKey) => _byKey[bindingKey];

  /// Snapshot of registered bindingKey → pid pairs.
  Map<String, int> get entries => Map.unmodifiable(_byKey);

  /// Same as [entries]; preferred name when feeding ProcessMetricsService.
  Map<String, int> get asMap => entries;
}
