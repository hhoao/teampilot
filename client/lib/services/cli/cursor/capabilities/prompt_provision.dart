import '../../../../services/io/filesystem.dart';
import '../../registry/capabilities/prompt_provision_capability.dart';
import '../provider/cursor_home_layout.dart';
import '../provider/cursor_role_rule_writer.dart';

/// cursor 把成员 prompt 写入 fake HOME 的 `~/.cursor/rules/role.mdc`。
/// 由 `CursorHomeProvisioner` 调用（装配点无 scope/paths delegate，只传
/// memberHome）；无 flag 传输，.mdc 自动加载。
///
/// 偏差说明（Task 6 控制器授权）：`CursorHomeProvisioner` 没有
/// `ConfigProfileDelegate`，无法在 ctx 里传 paths；因此本 capability 除
/// `ctx.paths` 外还接受构造注入的 [fs]/[layout] 兜底。装配点以
/// `CursorPromptProvisionCapability(fs: _fs, layout: _layout)` 构造，两路径
/// 写同一 fs/layout，行为零漂移；`ctx.paths` 优先（config_profile 阶段测试
/// 即走该路径）。
final class CursorPromptProvisionCapability
    implements PromptProvisionCapability {
  const CursorPromptProvisionCapability({this.fs, this.layout});

  final Filesystem? fs;
  final CursorHomeLayout? layout;

  @override
  Future<PromptProvisionContribution> provision(
    PromptProvisionContext ctx,
  ) async {
    final fs = ctx.paths?.fs ?? this.fs;
    final layout = ctx.paths != null
        ? CursorHomeLayout(pathContext: ctx.paths!.pathContext)
        : this.layout;
    final memberHome = ctx.memberHome;
    final member = ctx.member;
    if (fs == null ||
        layout == null ||
        memberHome == null ||
        memberHome.isEmpty ||
        member == null ||
        !member.isValid) {
      return const PromptProvisionContribution();
    }
    final rolePath = await CursorRoleRuleWriter(fs: fs, layout: layout).sync(
      memberHome: memberHome,
      member: member,
      forceTeamLeadDelegateMode: ctx.forceTeamLeadDelegateMode,
      mixed: ctx.mixed,
      pushDelivery: ctx.pushDelivery,
      additionalDirectories: const [],
    );
    if (rolePath == null) return const PromptProvisionContribution();
    return const PromptProvisionContribution(written: true);
  }
}
