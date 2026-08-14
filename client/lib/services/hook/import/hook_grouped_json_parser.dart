import 'dart:convert';

import 'hook_json_dialect.dart';

/// claude-family / codex 共享的分组 JSON 内核：
/// `{"hooks": {"<Event>": [{"matcher"?, "hooks": [handler...]}]}}`。
/// 支持只贴 hooks 段（根对象本身是事件 → 组 map）。
abstract final class HookGroupedJsonParser {
  HookGroupedJsonParser._();

  static List<RawHookEntry> parse(
    String jsonText,
    List<String> warnings, {
    Set<String> allowedTopLevelKeys = const {},
  }) {
    // 方言声明预留：内核暂不校验顶层未知键（保持宽容）。
    if (allowedTopLevelKeys.isEmpty) {
      // no-op：保留参数以表达方言声明意图。
    }
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

    Map<String, Object?>? groups;
    final hooks = root['hooks'];
    if (hooks is Map) {
      groups = hooks.cast<String, Object?>();
      if (groups.isEmpty) {
        warnings.add('hook_import_no_hooks');
        return const [];
      }
    } else if (root.containsKey('hooks')) {
      warnings.add('hook_import_bad_hooks_envelope');
      return const [];
    } else if (looksLikeGroups(root)) {
      groups = root;
    } else {
      warnings.add('hook_import_no_hooks');
      return const [];
    }

    final entries = <RawHookEntry>[];
    for (final groupEntry in groups.entries) {
      final event = groupEntry.key;
      final groupsList = groupEntry.value;
      if (groupsList is! List) {
        warnings.add('hook_import_bad_group_$event');
        continue;
      }
      for (final group in groupsList) {
        if (group is! Map) {
          warnings.add('hook_import_bad_group_$event');
          continue;
        }
        final g = group.cast<String, Object?>();
        final matcher = hookJsonString(g, 'matcher');
        final handlers = g['hooks'];
        if (handlers is! List) {
          warnings.add('hook_import_bad_group_$event');
          continue;
        }
        for (final handler in handlers) {
          if (handler is! Map) {
            warnings.add('hook_import_bad_handler_$event');
            continue;
          }
          final h = handler.cast<String, Object?>();
          final type = hookJsonString(h, 'type') ?? 'command';
          final timeout = hookJsonInt(h, 'timeout');
          final native = <String, Object?>{};
          final unsupported = <String>[];
          const consumed = {'type', 'command', 'url', 'headers', 'timeout'};
          for (final entry in h.entries) {
            if (consumed.contains(entry.key)) continue;
            native[entry.key] = entry.value;
            unsupported.add(entry.key);
          }
          switch (type) {
            case 'command':
              final command = hookJsonString(h, 'command');
              if (command == null) {
                warnings.add('hook_import_bad_handler_$event');
                continue;
              }
              entries.add(RawHookEntry(
                nativeEvent: event,
                matcher: matcher,
                type: 'command',
                command: command,
                timeoutSec: timeout,
                native: native,
                unsupportedFields: unsupported,
              ));
              break;
            case 'http':
              final url = hookJsonString(h, 'url');
              if (url == null) {
                warnings.add('hook_import_bad_handler_$event');
                continue;
              }
              entries.add(RawHookEntry(
                nativeEvent: event,
                matcher: matcher,
                type: 'http',
                url: url,
                headers: hookJsonStringMap(h, 'headers'),
                timeoutSec: timeout,
                native: native,
                unsupportedFields: unsupported,
              ));
              break;
            default:
              warnings.add('hook_import_type_unsupported_$type');
          }
        }
      }
    }
    return entries;
  }
}
