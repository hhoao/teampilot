import 'dart:convert';

import '../../../models/team_config.dart';
import 'hook_json_dialect.dart';

/// cursor：`~/.cursor/hooks.json`（`{"version":1,"hooks":{<event>:[扁平条目]}}`）。
/// 条目字段直接映射（matcher 在条目上）；`loop_limit`/`failClosed` 旁路保留；
/// `type: "prompt"` 跳过并 warning。
class CursorHooksJsonDialect implements HookJsonDialect {
  const CursorHooksJsonDialect();

  @override
  CliTool get cli => CliTool.cursor;

  @override
  List<RawHookEntry> parseJson(String jsonText, List<String> warnings) {
    final Object? decoded;
    try {
      decoded = jsonDecode(jsonText);
    } on FormatException {
      warnings.add('hook_import_invalid_json_shape');
      return const [];
    }
    if (decoded is! Map) {
      warnings.add('hook_import_invalid_json_shape');
      return const [];
    }
    final root = decoded.cast<String, Object?>();
    final hooks = root['hooks'];
    if (hooks is! Map) {
      warnings.add('hook_import_no_hooks');
      return const [];
    }
    final entries = <RawHookEntry>[];
    for (final groupEntry in hooks.cast<String, Object?>().entries) {
      final event = groupEntry.key;
      final list = groupEntry.value;
      if (list is! List) {
        warnings.add('hook_import_bad_group_$event');
        continue;
      }
      for (final item in list) {
        if (item is! Map) {
          warnings.add('hook_import_bad_handler_$event');
          continue;
        }
        final h = item.cast<String, Object?>();
        final type = hookJsonString(h, 'type') ?? 'command';
        if (type != 'command') {
          warnings.add('hook_import_type_unsupported_$type');
          continue;
        }
        final command = hookJsonString(h, 'command');
        if (command == null) {
          warnings.add('hook_import_bad_handler_$event');
          continue;
        }
        final native = <String, Object?>{};
        final unsupported = <String>[];
        const consumed = {'type', 'command', 'matcher', 'timeout'};
        for (final entry in h.entries) {
          if (consumed.contains(entry.key)) continue;
          native[entry.key] = entry.value;
          unsupported.add(entry.key);
        }
        entries.add(RawHookEntry(
          nativeEvent: event,
          matcher: hookJsonString(h, 'matcher'),
          type: 'command',
          command: command,
          timeoutSec: hookJsonInt(h, 'timeout'),
          native: native,
          unsupportedFields: unsupported,
        ));
      }
    }
    return entries;
  }
}
