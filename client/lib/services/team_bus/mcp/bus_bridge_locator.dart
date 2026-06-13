import 'dart:io';

import 'package:meta/meta.dart';

/// 解析 `teammate_bus_bridge` 可执行文件的路径（见 `tools/teammate_bus_bridge/`）。
///
/// 桥接让 claude 经 stdio（无 6 分钟 fetch 死线）阻塞在 `wait_for_message`，再转回
/// app 的 loopback bus。解析顺序：
///   1. 环境变量 `TEAMPILOT_BUS_BRIDGE`（开发：指向 `dart compile exe` 的产物）。
///   2. 与 app 可执行文件同目录（发布：随包分发）。
///   3. 都没有 → 返回 null，调用方回落到 HTTP 传输（不破坏现状）。
///
/// 除存在性外还验证当前 CPU 能执行该二进制（避免 DMG 里仅有 arm64 slice、
/// Intel Mac 上 stdio 配置指向无法运行的 exe）。
class BusBridgeLocator {
  const BusBridgeLocator._();

  static const envOverride = 'TEAMPILOT_BUS_BRIDGE';

  static String get _exeName =>
      Platform.isWindows ? 'teammate_bus_bridge.exe' : 'teammate_bus_bridge';

  /// 返回可用的桥接 exe 绝对路径，找不到或无法在当前 CPU 执行时返回 null。
  static String? resolve() {
    final override = Platform.environment[envOverride]?.trim();
    if (override != null && override.isNotEmpty) {
      return isRunnableExecutable(override) ? override : null;
    }
    try {
      final dir = File(Platform.resolvedExecutable).parent.path;
      final candidate = '$dir${Platform.pathSeparator}$_exeName';
      if (isRunnableExecutable(candidate)) return candidate;
    } catch (_) {
      // resolvedExecutable 不可用（极少见）→ 视作未找到。
    }
    return null;
  }

  /// 路径存在且 OS 接受在当前 CPU 上启动（架构不匹配会返回 false）。
  @visibleForTesting
  static bool isRunnableExecutable(String path) {
    if (!File(path).existsSync()) return false;
    try {
      // Bridge 无参数会立刻 exit(2)（缺 --bus-url）；我们只关心能否被加载执行。
      Process.runSync(path, const <String>[], runInShell: false);
      return true;
    } on ProcessException {
      return false;
    }
  }
}
