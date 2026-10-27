import '../../../../models/hook_entry.dart';
import '../../../../models/hook_event.dart';
import '../../../../models/team_config.dart';
import '../../registry/capabilities/hook_capability.dart';
import '../../registry/config_profile/claude_family_hook_writer.dart';

/// CodeBuddy hook renderer.
///
/// The CLI reads Claude Code's `settings.json` `hooks` dialect (identical
/// event names, matcher + command/http entries), so rendering reuses
/// [ClaudeFamilyHookWriter]. [nativeEvent] still goes through the shared
/// matrix so UI support badges stay capability-driven.
final class CodebuddyHookWriter implements HookCapability {
  const CodebuddyHookWriter({this.denyReason = 'TeamPilot hook policy'});

  final String denyReason;

  ClaudeFamilyHookWriter get _delegate =>
      ClaudeFamilyHookWriter(denyReason: denyReason);

  @override
  String? nativeEvent(HookEvent event) =>
      HookEventCapability.nativeEvent(event, CliTool.codebuddy);

  @override
  bool get supportsMatcher => true;

  @override
  bool get supportsHttp => true;

  @override
  bool get supportsPolicy => true;

  @override
  bool supportsEvent(HookEvent event) => nativeEvent(event) != null;

  @override
  HookWriteResult render({
    required List<HookEntry> entries,
    required HookRenderContext ctx,
  }) => _delegate.render(entries: entries, ctx: ctx);
}
