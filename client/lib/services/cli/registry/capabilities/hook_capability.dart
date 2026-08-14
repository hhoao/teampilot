import '../../../host/host_script_runner.dart';
import '../../../../models/hook_entry.dart';
import '../../../../models/hook_event.dart';
import '../../../hook/glue_script_builder.dart';
import '../cli_capability.dart';
import 'hook_registry.dart';

/// 渲染上下文：脚本落盘目录 + 运行器（方言） + 胶水生成器。
class HookRenderContext {
  const HookRenderContext({
    required this.hooksDir,
    required this.runner,
    required this.glueBuilder,
  });

  /// session 内脚本目录（绝对路径，work-plane 路径即机器路径）。
  final String hooksDir;

  /// 主机运行器（dialect：bash / powershell）。
  final HostScriptRunner? runner;

  final GlueScriptBuilder glueBuilder;
}

/// 一次 render 的输出：文件级配置片段 + 生成的脚本 + 警告。
class HookWriteResult {
  const HookWriteResult({
    this.configFragments = const {},
    this.scripts = const [],
    this.warnings = const [],
  });

  /// `Map<相对文件名, 配置内容>`，如 `{'settings.json': {...}}`、
  /// `{'config.toml': '...'}`、`{'hooks.json': {...}}`。
  final Map<String, Object?> configFragments;
  final List<GeneratedScript> scripts;
  final List<String> warnings;
}

/// 每 CLI 一个实现：把归一化 [HookEntry] 渲染为该 CLI 原生 hook 配置。
/// render 必须是纯函数（无 IO）——脚本经 [HookWriteResult.scripts] 返回，
/// 由装配点写盘。
abstract interface class HookCapability implements CliCapability {
  String? nativeEvent(HookEvent event);

  bool get supportsMatcher;
  bool get supportsHttp;
  bool get supportsPolicy;

  bool supportsEvent(HookEvent event) => nativeEvent(event) != null;

  HookWriteResult render({
    required List<HookEntry> entries,
    required HookRenderContext ctx,
  });
}
