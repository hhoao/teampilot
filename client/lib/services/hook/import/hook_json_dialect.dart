import 'package:flutter/foundation.dart';

import '../../../models/team_config.dart';

/// 方言解析产出的中间形态（保持 JSON 内顺序）。
@immutable
class RawHookEntry {
  const RawHookEntry({
    required this.nativeEvent,
    this.matcher,
    required this.type,
    this.command,
    this.url,
    this.headers = const {},
    this.timeoutSec,
    this.native = const {},
    this.unsupportedFields = const [],
    this.warnings = const [],
  });

  /// 原生事件名（claude/codex PascalCase 或 cursor 小写）。
  final String nativeEvent;
  final String? matcher;

  /// handler 类型：'command' | 'http'（其余已在方言层丢弃并 warning）。
  final String type;
  final String? command;
  final String? url;
  final Map<String, String> headers;
  final int? timeoutSec;

  /// 旁路：原生 handler 完整字段（零丢失）。
  final Map<String, Object?> native;

  /// 导入后不生效的字段名（预览标注）。
  final List<String> unsupportedFields;
  final List<String> warnings;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RawHookEntry &&
          nativeEvent == other.nativeEvent &&
          matcher == other.matcher &&
          type == other.type &&
          command == other.command &&
          url == other.url &&
          mapEquals(headers, other.headers) &&
          timeoutSec == other.timeoutSec &&
          mapEquals(native, other.native) &&
          listEquals(unsupportedFields, other.unsupportedFields) &&
          listEquals(warnings, other.warnings);

  @override
  int get hashCode => Object.hash(
    nativeEvent,
    matcher,
    type,
    command,
    url,
    Object.hashAllUnordered(headers.keys),
    Object.hashAllUnordered(headers.values),
    timeoutSec,
    Object.hashAllUnordered(native.keys),
    Object.hashAllUnordered(native.values),
    Object.hashAllUnordered(unsupportedFields),
    Object.hashAllUnordered(warnings),
  );
}

/// 每 CLI 一个实现：把该 CLI 的 hook JSON 解析为 [RawHookEntry] 列表。
/// 方言层只做结构解析（事件名/分组/handler 字段），不做归一化（事件映射、
/// 脚本提取在共享层）。
abstract interface class HookJsonDialect {
  CliTool get cli;
  List<RawHookEntry> parseJson(String jsonText, List<String> warnings);
}

String? hookJsonString(Map<String, Object?> map, String key) {
  final value = map[key];
  return value is String && value.isNotEmpty ? value : null;
}

int? hookJsonInt(Map<String, Object?> map, String key) {
  final value = map[key];
  return value is num ? value.toInt() : null;
}

Map<String, String> hookJsonStringMap(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value is! Map) return const {};
  final out = <String, String>{};
  for (final entry in value.entries) {
    final v = entry.value;
    if (v is String) out[entry.key.toString()] = v;
  }
  return out;
}

/// 路径形态 token：以 `/`、`~/`、`./`、`../` 开头，或含 `/` 且非 `-` 开头
/// （相对路径如 `scripts/x.py`）。
bool isPathLike(String token) {
  if (token.startsWith('-')) return false;
  return token.startsWith('/') ||
      token.startsWith('~/') ||
      token.startsWith('./') ||
      token.startsWith('../') ||
      token.contains('/');
}

String stripQuotes(String token) {
  if (token.length >= 2 &&
      ((token.startsWith('"') && token.endsWith('"')) ||
          (token.startsWith("'") && token.endsWith("'")))) {
    return token.substring(1, token.length - 1);
  }
  return token;
}

/// 根对象是否本身就是 hooks map（`{<Event>: [groups...]}`）。
bool looksLikeGroups(Map<String, Object?> root) {
  if (root.isEmpty) return false;
  return root.values.every((v) => v is List);
}
