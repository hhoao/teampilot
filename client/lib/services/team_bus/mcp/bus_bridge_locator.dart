import 'dart:io';

/// 解析 `teammate_bus_bridge` 可执行文件的路径（见 `tools/teammate_bus_bridge/`）。
///
/// 桥接让 claude 经 stdio（无 6 分钟 fetch 死线）阻塞在 `wait_for_message`，再转回
/// app 的 loopback bus。解析顺序：
///   1. 环境变量 `TEAMPILOT_BUS_BRIDGE`（开发：指向 `dart compile exe` 的产物）。
///   2. 与 app 可执行文件同目录（发布：随包分发）。
///   3. 都没有 → 返回 null，调用方回落到 HTTP 传输（不破坏现状）。
class BusBridgeLocator {
  const BusBridgeLocator._();

  static const envOverride = 'TEAMPILOT_BUS_BRIDGE';

  static String get _exeName =>
      Platform.isWindows ? 'teammate_bus_bridge.exe' : 'teammate_bus_bridge';

  /// 返回可用的桥接 exe 绝对路径，找不到返回 null。
  static String? resolve() {
    final override = Platform.environment[envOverride]?.trim();
    if (override != null && override.isNotEmpty && File(override).existsSync()) {
      return override;
    }
    try {
      final dir = File(Platform.resolvedExecutable).parent.path;
      final candidate = '$dir${Platform.pathSeparator}$_exeName';
      if (File(candidate).existsSync()) return candidate;
    } catch (_) {
      // resolvedExecutable 不可用（极少见）→ 视作未找到。
    }
    return null;
  }
}
