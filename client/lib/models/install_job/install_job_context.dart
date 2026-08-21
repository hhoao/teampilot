import 'dart:async';
import 'dart:io';

final class InstallJobContext {
  InstallJobContext({
    void Function(String label, {String? detail, double? fraction})? reportPhase,
    void Function({required int completed, required int total})? reportItems,
  })  : _reportPhase = reportPhase,
        _reportItems = reportItems;

  final void Function(String label, {String? detail, double? fraction})?
  _reportPhase;
  final void Function({required int completed, required int total})?
  _reportItems;

  bool _cancelled = false;
  final List<Process> _processes = [];
  final List<FutureOr<void> Function()> _cancelHooks = [];

  bool get isCancelled => _cancelled;

  void reportPhase(String label, {String? detail, double? fraction}) {
    _reportPhase?.call(label, detail: detail, fraction: fraction);
  }

  void reportItems({required int completed, required int total}) {
    _reportItems?.call(completed: completed, total: total);
  }

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
