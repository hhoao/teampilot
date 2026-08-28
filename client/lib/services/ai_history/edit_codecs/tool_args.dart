import 'dart:convert';

import 'package:ai_message_core/ai_message_core.dart';

/// Decodes args from [part.args] (already-parsed map) or [part.argsText] (JSON
/// string).  Returns null when neither source produces a non-empty map.
Map<String, Object?>? toolCallArgsMap(AiToolCallPart part) {
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

/// Returns the first value found among [keys] that is a non-empty String
/// (after trimming), or null if none match.
String? firstNonEmptyString(Map<String, Object?>? args, List<String> keys) {
  if (args == null) return null;
  for (final key in keys) {
    final value = args[key];
    if (value is String && value.trim().isNotEmpty) return value.trim();
  }
  return null;
}

/// Returns the string value for the first key in [keys] that is present in
/// [args], regardless of whether the string is empty.  Returns null when no
/// key is present or the value is not a String.
String? optionalString(Map<String, Object?>? args, List<String> keys) {
  if (args == null) return null;
  for (final key in keys) {
    if (!args.containsKey(key)) continue;
    final value = args[key];
    return value is String ? value : null;
  }
  return null;
}

/// Returns the first positive integer found among [keys] (>= 1), or null.
int? firstPositiveInt(Map<String, Object?>? args, List<String> keys) {
  if (args == null) return null;
  for (final key in keys) {
    final parsed = parsePositiveInt(args[key]);
    if (parsed != null) return parsed;
  }
  return null;
}

/// Parses [value] as a positive integer (>= 1).  Handles [int], [num], and
/// [String] representations.
int? parsePositiveInt(Object? value) {
  if (value is int && value >= 1) return value;
  if (value is num && value.isFinite && value >= 1) return value.toInt();
  if (value is String) {
    final parsed = int.tryParse(value.trim());
    if (parsed != null && parsed >= 1) return parsed;
  }
  return null;
}

/// Splits [text] by newline, returning an empty list for an empty string.
List<String> splitLines(String text) {
  if (text.isEmpty) return const [];
  return text.split('\n');
}

/// Matches [splitLines] length without allocating the line list.
int countSplitLines(String text) {
  if (text.isEmpty) return 0;
  var n = 1;
  for (var i = 0; i < text.length; i++) {
    if (text.codeUnitAt(i) == 0x0A) n++;
  }
  return n;
}

/// First [max] lines of [text] using the same split as [splitLines].
List<String> takeSplitLines(String text, int max) {
  if (text.isEmpty || max <= 0) return const [];
  final out = <String>[];
  var start = 0;
  for (var i = 0; i < text.length; i++) {
    if (text.codeUnitAt(i) != 0x0A) continue;
    out.add(text.substring(start, i));
    if (out.length >= max) return out;
    start = i + 1;
  }
  out.add(text.substring(start));
  return out;
}

/// Max [AiEditLine]s History cards materialize. Add/remove counts stay full.
const kAiEditHunkMaxEncodedLines = 500;
