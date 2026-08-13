import '../../models/hook_definition.dart';
import '../../models/hook_entry.dart';
import '../io/filesystem.dart';
import 'hook_repository.dart';

class ResolvedHooks {
  const ResolvedHooks({this.entries = const [], this.warnings = const []});

  final List<HookEntry> entries;
  final List<String> warnings;
}

/// 把启用的 hookIds（已按 team > expert > workspace 合并）解析为
/// [HookEntry] 列表：加载定义、读取托管脚本内容、未知 id / 缺脚本记 warning。
class HookLibraryResolver {
  HookLibraryResolver({
    required Filesystem fs,
    required String teampilotRoot,
    HookRepository? repository,
  }) : _repository =
           repository ?? HookRepository(fs: fs, teampilotRoot: teampilotRoot);

  final HookRepository _repository;

  Future<ResolvedHooks> resolve(List<String> hookIds) async {
    final entries = <HookEntry>[];
    final warnings = <String>[];
    final seen = <String>{};
    for (final raw in hookIds) {
      final id = raw.trim();
      if (id.isEmpty || seen.contains(id)) continue;
      seen.add(id);
      final definition = await _repository.load(id);
      if (definition == null) {
        warnings.add('hook_missing_$id');
        continue;
      }
      final action = await _resolveAction(definition, warnings);
      if (action == null) continue;
      entries.add(_toEntry(definition, action));
    }
    return ResolvedHooks(
      entries: List.unmodifiable(entries),
      warnings: List.unmodifiable(warnings),
    );
  }

  Future<HookAction?> _resolveAction(
    HookDefinition definition,
    List<String> warnings,
  ) async {
    final action = definition.action;
    if (action is CommandHookAction && action.command != null) return action;
    if (action is HttpHookAction) return action;
    if (action is CommandHookAction && action.fileName != null) {
      final content = await _repository.readScript(
        definition.id,
        action.fileName!,
      );
      if (content == null || content.trim().isEmpty) {
        warnings.add('hook_script_missing_${definition.id}_${action.fileName}');
        return null;
      }
      return CommandHookAction.script(
        fileName: action.fileName!,
        scriptContent: content,
      );
    }
    warnings.add('hook_invalid_action_${definition.id}');
    return null;
  }

  HookEntry _toEntry(HookDefinition definition, HookAction action) =>
      HookEntry(
        id: definition.id,
        source: HookSource.userLibrary,
        event: definition.event,
        matcher: definition.matcher,
        action: action,
        policy: definition.policy,
        timeout: definition.timeoutSec == null
            ? null
            : Duration(seconds: definition.timeoutSec!),
        env: definition.env,
      );
}
