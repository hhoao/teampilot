import 'cli_asset_registry.dart';
import 'cli_config_asset.dart';

/// 统一 hook 声明（能力侧只写这个，不碰原始 map）。
class CliHookSpec {
  const CliHookSpec({
    required this.event,
    this.url,
    this.headers = const {},
    this.timeout,
    this.command,
    this.blockOnDecision = false,
  });

  /// 规范事件名：promptSubmit / stop / questionAsked / permissionAsked / ...
  final String event;

  /// http 类 hook 目标（与 [command] 二选一）。
  final String? url;
  final Map<String, String> headers;
  final Duration? timeout;

  /// command 类 hook（脚本路径或内容引用）。
  final String? command;

  /// 是否需要解析 decision:block（idle 类钩子）。
  final bool blockOnDecision;
}

class GeneratedScript {
  const GeneratedScript({required this.fileName, required this.content});
  final String fileName;
  final String content;
}

/// hooks 特化：只加"资产 → 配置文件片段"。
abstract interface class HookRegistry extends CliAssetRegistry<CliHookSpec> {
  /// 规范事件 → CLI 原生事件名映射。
  Map<String, String> get eventNameMap;

  /// 纯函数：资产集 → 该 CLI 的配置文件片段（幂等）。
  /// 输出为文件级（`Map<relativePath, content>`），不假设进 settings.json。
  Map<String, Object?> render(List<CliConfigAsset<CliHookSpec>> assets);

  /// command 类 hook 的脚本内容。
  List<GeneratedScript> generateScripts(List<CliConfigAsset<CliHookSpec>> assets);
}
