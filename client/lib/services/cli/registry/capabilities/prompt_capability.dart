import '../../../../models/team_config.dart';
import '../cli_capability.dart';
import '../config_profile/config_profile_context.dart';

enum PromptScope { cli, member, team, expert, workspace, global }

enum PromptMergeRole { replace, append, section }

class PromptSpec {
  const PromptSpec({
    required this.id,
    required this.title,
    required this.content,
    this.scope = PromptScope.cli,
    this.mergeRole = PromptMergeRole.replace,
  });

  final String id;
  final String title;
  final String content;
  final PromptScope scope;
  final PromptMergeRole mergeRole;
}

class PromptVirtualizeContext {
  const PromptVirtualizeContext({
    this.paths,
    this.scope,
    this.member,
    this.memberHome,
  });

  final ConfigProfileDelegate? paths;
  final LaunchProfileScope? scope;
  final TeamMemberConfig? member;

  /// cursor 专用：fake HOME，由装配点解析后传入。
  final String? memberHome;
}

/// 每 CLI 声明"成员 prompt 组合 + 写入目标 + 传输贡献"。
///
/// 装配点（config_profile / cursor home provisioner）只调 [materialize] 并合并
/// [PromptMaterializeResult]；prompt 逻辑全部收敛到实现里。
/// 各实现只读自己需要的 ctx 字段，必需输入缺失时返回空贡献（written: false）：
/// - claude / flashskyai / codex / opencode：需要 [PromptMaterializeContext.paths]
///   与 [PromptMaterializeContext.scope]（sessionToolDir 定位）；
/// - cursor：需要 [PromptMaterializeContext.memberHome]；写入源（ctx.paths 或构造
///   注入 fs/layout）齐备才写入，仅缺写入源时抛 [StateError]。
abstract interface class PromptCapability implements CliCapability {
  /// 源契约：声明我提供的 prompt 虚拟实例（纯函数，无 IO）。
  List<PromptSpec> virtualize(PromptVirtualizeContext ctx);

  /// 物化器契约：把收集合并后的 PromptSpec 列表写入 CLI 原生位置。
  Future<PromptMaterializeResult> materialize(PromptMaterializeContext ctx);
}

class PromptMaterializeContext {
  const PromptMaterializeContext({
    this.paths,
    this.scope,
    this.member,
    this.forceTeamLeadDelegateMode = false,
    this.mixed = false,
    this.pushDelivery = false,
    this.additionalDirectories = const [],
    this.memberHome,
  });

  final ConfigProfileDelegate? paths;
  final LaunchProfileScope? scope;
  final TeamMemberConfig? member;
  final bool forceTeamLeadDelegateMode;
  final bool mixed;
  final bool pushDelivery;

  /// 已 normalize 的工作面路径；只有 opencode 的实现把它拼进 prompt。
  final List<String> additionalDirectories;

  /// cursor 专用：fake HOME，由装配点解析后传入。
  final String? memberHome;
}

class PromptMaterializeResult {
  const PromptMaterializeResult({
    this.environment = const {},
    this.written = false,
  });

  /// 传输 env（claude/flashskyai 的 `TEAMPILOT_APPEND_SYSTEM_PROMPT_FILE`）。
  final Map<String, String> environment;

  /// 是否发生了写入（装配点借此并入 changed）。
  final bool written;
}
