import 'dart:io';

bool _enabled(String name) {
  final value = Platform.environment[name]?.trim().toLowerCase();
  return value == '1' || value == 'true' || value == 'yes' || value == 'on';
}

class PerfFlags {
  const PerfFlags._();

  static bool get noResume => _enabled('FLASHSKYAI_PERF_NO_RESUME');
  static bool get noOpenSessionEmit =>
      _enabled('FLASHSKYAI_PERF_NO_OPEN_SESSION_EMIT');
  static bool get noTerminalSessionCreate =>
      _enabled('FLASHSKYAI_PERF_NO_TERMINAL_SESSION_CREATE');
  static bool get noSessionTabsState =>
      _enabled('FLASHSKYAI_PERF_NO_SESSION_TABS_STATE');
  static bool get noActiveSessionState =>
      _enabled('FLASHSKYAI_PERF_NO_ACTIVE_SESSION_STATE');
  static bool get noPtyStart => _enabled('FLASHSKYAI_PERF_NO_PTY_START');
  static bool get noPtyOutput => _enabled('FLASHSKYAI_PERF_NO_PTY_OUTPUT');
  static bool get noPtyHandlers => _enabled('FLASHSKYAI_PERF_NO_PTY_HANDLERS');
  static bool get noRunningEmit => _enabled('FLASHSKYAI_PERF_NO_RUNNING_EMIT');
  static bool get noTerminalView =>
      _enabled('FLASHSKYAI_PERF_NO_TERMINAL_VIEW');
}
