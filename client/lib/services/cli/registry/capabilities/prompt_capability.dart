import '../../../../models/team_config.dart';
import '../../../resource/contribution/resource_assembly_error.dart';
import '../../../resource/contribution/resource_assembly_result.dart';
import '../../../resource/contribution/prompt_document.dart';
import '../cli_capability.dart';
import '../config_profile/config_profile_context.dart';

export '../../../resource/contribution/prompt_document.dart';
export '../../../resource/providers/prompt_contribution_provider.dart';

/// Compatibility context for callers that still need to construct the old
/// source-side inputs during migration. Prompt capabilities no longer expose
/// a virtualize method; providers use [PromptProviderContext].
class PromptVirtualizeContext {
  const PromptVirtualizeContext({
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

/// Each CLI declares a target writer for an assembled prompt document.
///
/// 各实现只读自己需要的 ctx 字段，必需输入缺失时返回空贡献（written: false）：
/// - claude / flashskyai / codex / opencode：需要 [PromptMaterializeContext.paths]
///   与 [PromptMaterializeContext.scope]（sessionToolDir 定位）；
/// - cursor：需要 [PromptMaterializeContext.memberHome]；写入源（ctx.paths 或构造
///   注入 fs/layout）齐备才写入，仅缺写入源时抛 [StateError]。
abstract interface class PromptCapability implements CliCapability {
  /// Writes the assembled document to the CLI-native target.
  Future<PromptMaterializeResult> materialize(
    PromptMaterializeContext ctx, {
    required PromptDocument document,
  });
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
    this.assembly,
  });

  /// 传输 env（claude/flashskyai 的 `TEAMPILOT_APPEND_SYSTEM_PROMPT_FILE`）。
  final Map<String, String> environment;

  /// 是否发生了写入（装配点借此并入 changed）。
  final bool written;

  /// Diagnostics produced while assembling the document consumed by the
  /// materializer. Direct capability callers may leave this null.
  final ResourceAssemblyResult? assembly;

  List<ResourceAssemblyDiagnostic> get diagnostics =>
      assembly?.diagnostics ?? const [];
}
