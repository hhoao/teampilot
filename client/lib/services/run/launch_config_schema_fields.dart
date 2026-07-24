import 'package:flutter/foundation.dart';

/// How a JSON-schema property maps to a launch-config form control.
enum LaunchConfigSchemaFieldType {
  string,
  stringArray,
  stringMap,
  boolean,
  enumValue,
  unsupported,
}

/// Descriptor for one property in a launch type `configurationSchema`.
@immutable
class LaunchConfigSchemaField {
  const LaunchConfigSchemaField({
    required this.key,
    required this.type,
    this.title,
    this.enumValues,
  });

  final String key;
  final LaunchConfigSchemaFieldType type;

  /// Optional schema `title`; when absent UI uses a title-cased [key].
  final String? title;

  /// Allowed values when [type] is [LaunchConfigSchemaFieldType.enumValue].
  final List<String>? enumValues;

  String get label {
    final t = title?.trim();
    if (t != null && t.isNotEmpty) return t;
    if (key.isEmpty) return key;
    return '${key[0].toUpperCase()}${key.substring(1)}';
  }
}

/// Extracts ordered field descriptors from a JSON-schema-shaped map.
///
/// Reads `properties` keys; unknown property shapes become
/// [LaunchConfigSchemaFieldType.unsupported] (form may skip them).
List<LaunchConfigSchemaField> launchConfigSchemaFields(
  Map<String, Object?> schema,
) {
  final raw = schema['properties'];
  if (raw is! Map) return const [];

  final fields = <LaunchConfigSchemaField>[];
  for (final entry in raw.entries) {
    final key = entry.key.toString();
    final prop = entry.value;
    final propMap = prop is Map
        ? prop.map((k, v) => MapEntry(k.toString(), v))
        : const <String, Object?>{};
    final type = _inferFieldType(propMap);
    final title = propMap['title'] is String
        ? (propMap['title'] as String)
        : null;
    fields.add(
      LaunchConfigSchemaField(
        key: key,
        type: type,
        title: title,
        enumValues: _enumValues(propMap),
      ),
    );
  }
  return fields;
}

List<String> parseLaunchArgsText(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return const [];
  return trimmed.split(RegExp(r'\s+'));
}

Map<String, String> parseLaunchEnvText(String text) {
  final result = <String, String>{};
  for (final line in text.split('\n')) {
    final trimmed = line.trimRight();
    if (trimmed.trim().isEmpty) continue;
    final eq = trimmed.indexOf('=');
    if (eq <= 0) continue;
    result[trimmed.substring(0, eq)] = trimmed.substring(eq + 1);
  }
  return result;
}

String stringifyLaunchArgs(List<String> args) => args.join(' ');

String stringifyLaunchEnv(Map<String, String> env) =>
    env.entries.map((e) => '${e.key}=${e.value}').join('\n');

LaunchConfigSchemaFieldType _inferFieldType(Map<String, Object?> prop) {
  final type = prop['type'];
  final enumRaw = prop['enum'];
  if (enumRaw is List && enumRaw.isNotEmpty) {
    return LaunchConfigSchemaFieldType.enumValue;
  }
  if (type == 'string') return LaunchConfigSchemaFieldType.string;
  if (type == 'boolean') return LaunchConfigSchemaFieldType.boolean;
  if (type == 'array') {
    final items = prop['items'];
    if (items is Map && items['type'] == 'string') {
      return LaunchConfigSchemaFieldType.stringArray;
    }
  }
  if (type == 'object') {
    final additional = prop['additionalProperties'];
    if (additional is Map && additional['type'] == 'string') {
      return LaunchConfigSchemaFieldType.stringMap;
    }
    if (additional == true) {
      return LaunchConfigSchemaFieldType.stringMap;
    }
  }
  return LaunchConfigSchemaFieldType.unsupported;
}

List<String>? _enumValues(Map<String, Object?> prop) {
  final raw = prop['enum'];
  if (raw is! List || raw.isEmpty) return null;
  return [for (final e in raw) e.toString()];
}
