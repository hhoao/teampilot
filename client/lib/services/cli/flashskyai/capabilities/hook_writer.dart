import '../../../../models/hook_entry.dart';
import '../../../../models/hook_event.dart';
import '../../../../models/team_config.dart';
import '../../registry/capabilities/hook_capability.dart';
import '../../registry/capabilities/hook_registry.dart';
import '../../registry/config_profile/claude_family_hook_writer.dart';
import 'stop_idle_hook.dart';

/// FlashskyAI hook renderer.
///
/// Ordinary entries use the Claude-family settings dialect. Bus-idle entries
/// remain neutral HTTP contributions until this target renderer converts them
/// to FlashskyAI's command/exit-2 contract. Script IO is performed by
/// [ManagedHookProvisioner], which consumes the returned [GeneratedScript].
final class FlashskyaiHookWriter implements HookCapability {
  const FlashskyaiHookWriter({this.denyReason = 'TeamPilot hook policy'});

  final String denyReason;

  ClaudeFamilyHookWriter get _delegate =>
      ClaudeFamilyHookWriter(denyReason: denyReason);

  @override
  String? nativeEvent(HookEvent event) =>
      HookEventCapability.nativeEvent(event, CliTool.flashskyai);

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
  }) {
    final idleEntries = <HookEntry>[];
    final ordinaryEntries = <HookEntry>[];
    for (final entry in entries) {
      if (_isBusIdleEntry(entry)) {
        idleEntries.add(entry);
      } else {
        ordinaryEntries.add(entry);
      }
    }

    final ordinary = _delegate.render(entries: ordinaryEntries, ctx: ctx);
    if (idleEntries.isEmpty) return ordinary;

    var settings =
        (ordinary.configFragments['settings.json'] as Map?)
            ?.cast<String, Object?>() ??
        const <String, Object?>{};
    final scripts = <GeneratedScript>[...ordinary.scripts];
    var scriptIndex = 0;
    for (final entry in idleEntries) {
      // The legacy FlashskyAI path installs the bus redirect only on Stop;
      // StopFailure is intentionally consumed here so it cannot fall back to
      // Claude-family type:http output.
      if (entry.event != HookEvent.stop) continue;
      final action = entry.action;
      if (action is! HttpHookAction) continue;

      final fileName = scriptIndex == 0
          ? flashskyaiStopIdleScriptFileName
          : 'teammate-bus-stop-idle-${_safeFileToken(entry.id)}.sh';
      final scriptDirectory = ctx.generatedScriptDirectory ?? ctx.hooksDir;
      final scriptPath = '$scriptDirectory/$fileName';
      scripts.add(
        GeneratedScript(
          fileName: fileName,
          targetDirectory: ctx.generatedScriptDirectory,
          content: flashskyaiStopIdleScriptForHttp(
            url: action.url,
            headers: action.headers,
          ),
        ),
      );
      settings = mergeFlashskyaiStopIdleHook(settings, scriptPath);
      scriptIndex++;
    }

    return HookWriteResult(
      configFragments: {...ordinary.configFragments, 'settings.json': settings},
      scripts: scripts,
      warnings: ordinary.warnings,
    );
  }

  static bool _isBusIdleEntry(HookEntry entry) =>
      entry.source == HookSource.managed &&
      entry.id.startsWith('teampilot-bus-idle-') &&
      entry.blockOnDecision &&
      entry.action is HttpHookAction;

  static String _safeFileToken(String value) =>
      value.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
}
