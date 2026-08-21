import 'dart:async';
import 'dart:io';

final class InstallJobContext {
  bool _cancelled = false;
  final List<Process> _processes = [];
  final List<FutureOr<void> Function()> _cancelHooks = [];

  bool get isCancelled => _cancelled;

  void requestCancel() => _cancelled = true;

  void registerProcess(Process process) => _processes.add(process);

  void registerCancelHook(FutureOr<void> Function() hook) =>
      _cancelHooks.add(hook);

  Future<void> forceKill() async {
    _cancelled = true;
    for (final process in _processes) {
      try {
        process.kill(ProcessSignal.sigterm);
      } on Object {
        // Best effort.
      }
    }
    for (final hook in _cancelHooks) {
      final result = hook();
      if (result is Future<void>) await result;
    }
  }
}
