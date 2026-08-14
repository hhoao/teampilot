import '../../../models/hook_definition.dart';
import '../../../models/hook_entry.dart';
import '../../../models/hook_event.dart';
import '../../../models/team_config.dart';
import '../../io/filesystem.dart';
import 'claude_family_hooks_json_dialect.dart';
import 'codex_hooks_json_dialect.dart';
import 'cursor_hooks_json_dialect.dart';
import 'hook_event_name_mapper.dart';
import 'hook_json_dialect.dart';
import 'hook_script_extractor.dart';

/// 一条可导入的 hook（预览与落库共用）。
class HookImportDraft {
  const HookImportDraft({
    required this.definition,
    this.scriptFileName,
    this.scriptContent,
    this.unsupportedFields = const [],
    this.warnings = const [],
  });

  final HookDefinition definition;

  /// ScriptCopy 时需写入库的脚本文件名（`hooks/{id}/{fileName}`）。
  final String? scriptFileName;
  final String? scriptContent;

  /// 导入后不生效的字段名（预览标注）。
  final List<String> unsupportedFields;
  final List<String> warnings;
}

class HookImportResult {
  const HookImportResult({this.drafts = const [], this.warnings = const []});

  final List<HookImportDraft> drafts;
  final List<String> warnings;
}

/// 通用解析入口：CLI 选择 + JSON 文本 → 归一化 drafts。
class HookImportParser {
  HookImportParser({
    required Filesystem fs,
    required String teampilotRoot,
    String? homeDir,
  }) : _fs = fs,
       _teampilotRoot = teampilotRoot,
       _homeDir = homeDir;

  final Filesystem _fs;
  final String _teampilotRoot;
  final String? _homeDir;

  static final Map<CliTool, HookJsonDialect> _dialects = {
    CliTool.claude: const ClaudeFamilyHooksJsonDialect(),
    CliTool.flashskyai: const ClaudeFamilyHooksJsonDialect(),
    CliTool.codex: const CodexHooksJsonDialect(),
    CliTool.cursor: const CursorHooksJsonDialect(),
  };

  Future<HookImportResult> parseJson({
    required CliTool cli,
    required String jsonText,
  }) async {
    final dialect = _dialects[cli];
    if (dialect == null) {
      return HookImportResult(warnings: ['hook_import_cli_unsupported_${cli.name}']);
    }
    final warnings = <String>[];
    final List<RawHookEntry> raw;
    try {
      raw = dialect.parseJson(jsonText, warnings);
    } on FormatException catch (e) {
      warnings.add('hook_import_invalid_json: ${e.message}');
      return HookImportResult(warnings: warnings);
    }

    final extractor = HookScriptExtractor(fs: _fs, homeDir: _homeDir);
    final drafts = <HookImportDraft>[];
    for (final entry in raw) {
      final event = HookEventNameMapper.map(cli, entry.nativeEvent);
      if (event == null) {
        warnings.add('hook_import_event_unsupported_${entry.nativeEvent}');
        continue;
      }
      final id = hookImportId(event, entry);
      final HookDefinition definition;
      String? scriptFileName;
      String? scriptContent;
      if (entry.type == 'http') {
        definition = HookDefinition(
          id: id,
          name: event.name,
          event: event,
          matcher: entry.matcher,
          action: HttpHookAction(
            url: entry.url!,
            headers: entry.headers,
          ),
          timeoutSec: entry.timeoutSec,
          native: entry.native.isEmpty ? null : entry.native,
        );
      } else {
        final command = entry.command!;
        final extraction = await extractor.extract(command);
        switch (extraction) {
          case ScriptCopy copy:
            scriptFileName = copy.fileName;
            scriptContent = copy.content;
            definition = HookDefinition(
              id: id,
              name: event.name,
              event: event,
              matcher: entry.matcher,
              action: CommandHookAction.raw(
                '${copy.interpreter} $_teampilotRoot/hooks/$id/${copy.fileName}',
              ),
              timeoutSec: entry.timeoutSec,
              native: entry.native.isEmpty ? null : entry.native,
            );
          case RawCommand():
            definition = HookDefinition(
              id: id,
              name: event.name,
              event: event,
              matcher: entry.matcher,
              action: CommandHookAction.raw(command),
              timeoutSec: entry.timeoutSec,
              native: entry.native.isEmpty ? null : entry.native,
            );
        }
      }
      drafts.add(HookImportDraft(
        definition: definition,
        scriptFileName: scriptFileName,
        scriptContent: scriptContent,
        unsupportedFields: entry.unsupportedFields,
        warnings: entry.warnings,
      ));
    }
    return HookImportResult(drafts: drafts, warnings: warnings);
  }
}

/// 确定性 id：`import-<fnv1a 64 位哈希十六进制前 12 位>`。
/// 同一条目重复导入 → 同 id → upsert 覆盖（幂等）。
String hookImportId(HookEvent event, RawHookEntry entry) {
  final key =
      '${event.name}|${entry.matcher ?? ''}|${entry.command ?? entry.url ?? ''}';
  return 'import-${_fnv1aHex(key).substring(0, 12)}';
}

String _fnv1aHex(String input) {
  var hash = 0xcbf29ce484222325;
  for (final codeUnit in input.codeUnits) {
    hash ^= codeUnit;
    hash = (hash * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF;
  }
  return (hash & 0xFFFFFFFFFFFF).toRadixString(16).padLeft(12, '0');
}
