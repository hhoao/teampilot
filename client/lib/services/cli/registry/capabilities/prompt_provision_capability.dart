import '../../../../models/team_config.dart';
import '../cli_capability.dart';
import '../config_profile/config_profile_context.dart';

/// 每 CLI 声明"成员 prompt 组合 + 写入目标 + 传输贡献"。
///
/// 装配点（config_profile / cursor home provisioner）只调 [provision] 并合并
/// [PromptProvisionContribution]；prompt 逻辑全部收敛到实现里。
/// 各实现只读自己需要的 ctx 字段，必需输入缺失时返回空贡献（written: false）：
/// - claude / flashskyai / codex / opencode：需要 [PromptProvisionContext.paths]
///   与 [PromptProvisionContext.scope]（sessionToolDir 定位）；
/// - cursor：需要 [PromptProvisionContext.memberHome]；写入源（ctx.paths 或构造
///   注入 fs/layout）齐备才写入，仅缺写入源时抛 [StateError]。
abstract interface class PromptProvisionCapability implements CliCapability {
  Future<PromptProvisionContribution> provision(PromptProvisionContext ctx);
}

class PromptProvisionContext {
  const PromptProvisionContext({
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

class PromptProvisionContribution {
  const PromptProvisionContribution({
    this.environment = const {},
    this.written = false,
  });

  /// 传输 env（claude/flashskyai 的 `TEAMPILOT_APPEND_SYSTEM_PROMPT_FILE`）。
  final Map<String, String> environment;

  /// 是否发生了写入（装配点借此并入 changed）。
  final bool written;
}
