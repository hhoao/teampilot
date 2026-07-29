import 'dart:convert';

import 'message.dart';

const editPathKeys = ['file_path', 'path', 'file', 'target_file'];
const editOldStringKeys = ['old_string', 'oldString'];
const editNewStringKeys = ['new_string', 'newString'];
const editStartLineKeys = ['start_line', 'startLine'];

Map<String, Object?>? editArgsMap(AiToolCallPart part) {
  if (part.args != null && part.args!.isNotEmpty) return part.args;
  final text = part.argsText?.trim();
  if (text == null || text.isEmpty) return null;
  try {
    final decoded = jsonDecode(text);
    if (decoded is! Map) return null;
    return {
      for (final e in decoded.entries) e.key.toString(): e.value,
    };
  } catch (_) {
    return null;
  }
}

String? editFirstNonEmptyString(Map<String, Object?>? args, List<String> keys) {
  if (args == null) return null;
  for (final key in keys) {
    final value = args[key];
    if (value is String && value.isNotEmpty) return value;
  }
  return null;
}

/// Returns the string when [keys] is present with a String value (including
/// empty). Null when no key is present or the value is not a String.
String? editOptionalString(Map<String, Object?>? args, List<String> keys) {
  if (args == null) return null;
  for (final key in keys) {
    if (!args.containsKey(key)) continue;
    final value = args[key];
    return value is String ? value : null;
  }
  return null;
}

int? editFirstPositiveInt(Map<String, Object?>? args, List<String> keys) {
  if (args == null) return null;
  for (final key in keys) {
    final parsed = editParsePositiveInt(args[key]);
    if (parsed != null) return parsed;
  }
  return null;
}

int? editParsePositiveInt(Object? value) {
  if (value is int && value >= 1) return value;
  if (value is num && value >= 1) return value.toInt();
  if (value is String) {
    final parsed = int.tryParse(value.trim());
    if (parsed != null && parsed >= 1) return parsed;
  }
  return null;
}

List<String> splitEditLines(String text) {
  if (text.isEmpty) return const [];
  return text.split('\n');
}
