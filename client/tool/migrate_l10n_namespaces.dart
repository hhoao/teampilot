// One-off migration tool: split flat ARB keys into per-feature slang namespace
// files under lib/i18n/.
//
// Usage: cd client && dart run tool/migrate_l10n_namespaces.dart [--dry-run]
//
// Grouping:
//  - longest-prefix match: multi-word prefixes in _overrides first, then the
//    first camelCase word if its group has >= _autoThreshold keys, else the key
//    stays in the root `_default` namespace (access path unchanged, so orphan
//    call sites need no edits).
//  - sub-key = key minus prefix, first letter lowercased
//    (`fileTreeImportSummary` -> fileTree.importSummary).
//
// Value conversion (slang JSON semantics; braces interpolation):
//  - typed ARB placeholder -> `{p: int}` / `{p: String}` (untyped stays `{p}`
//    and becomes Object, matching current generated signatures)
//  - ICU plural -> `"subKey(param=p)": {"one": ..., "other": ...}` with
//    `{p: int}` inside branch values so the generated param type stays int
//  - `@key` descriptions become `"@subKey": "..."` comments
//
// Also emits tool/l10n_migration_report.md (grouping stats + orphan list) and
// writes the flat-key -> access-path map to tool/l10n_key_map.json for the
// call-site codemod.

import 'dart:convert';
import 'dart:io';

const _overrides = <String, String>{
  'managedProviders': 'managedProviders',
  'sessionUsage': 'sessionUsage',
  'homeWorkspace': 'homeWorkspace',
  'appProvider': 'appProvider',
  'sshProfile': 'sshProfile',
  'gitGraph': 'gitGraph',
  'fileTree': 'fileTree',
  'teamHub': 'teamHub',
};

const _autoThreshold = 8;
const _defaultNs = '_default';

void main(List<String> args) {
  final dryRun = args.contains('--dry-run');
  final en = _loadArb('lib/l10n/app_en.arb');
  final zh = _loadArb('lib/l10n/app_zh.arb');

  final keys = en.keys.where((k) => !k.startsWith('@')).toList()..sort();
  final missing = keys.where((k) => !zh.containsKey(k)).toList();
  final extra = zh.keys
      .where((k) => !k.startsWith('@') && !en.containsKey(k))
      .toList();
  if (missing.isNotEmpty || extra.isNotEmpty) {
    stderr.writeln('en/zh key mismatch: missing=$missing extra=$extra');
    exit(1);
  }

  // First-word frequency for auto grouping.
  final firstWordCount = <String, int>{};
  for (final k in keys) {
    final w = _firstWord(k);
    firstWordCount[w] = (firstWordCount[w] ?? 0) + 1;
  }

  String namespaceOf(String key) {
    for (final prefix in _overrides.keys) {
      if (key.startsWith(prefix) && key.length > prefix.length) {
        return _overrides[prefix]!;
      }
    }
    final w = _firstWord(key);
    if ((firstWordCount[w] ?? 0) >= _autoThreshold && key.length >= w.length) {
      return w;
    }
    return _defaultNs;
  }

  String subKeyOf(String key, String ns) {
    if (ns == _defaultNs) return key;
    // Strip the matched prefix (override word or first word).
    final prefix =
        _overrides.entries
            .where((e) => e.value == ns && key.startsWith(e.key))
            .map((e) => e.key)
            .toList()
          ..sort((a, b) => b.length.compareTo(a.length));
    final stripped = prefix.isNotEmpty
        ? key.substring(prefix.first.length)
        : key.substring(_firstWord(key).length);
    // Key equals its own namespace name (`session` -> session.session) to
    // avoid a root/ns name collision in the generated tree.
    if (stripped.isEmpty) return key;
    return stripped[0].toLowerCase() + stripped.substring(1);
  }

  // Group.
  final files = <String, Map<String, Object?>>{}; // ns -> subKey -> value
  final filesZh = <String, Map<String, Object?>>{};
  final keyMap = <String, List<String>>{}; // flat key -> [ns, subKey]
  final orphans = <String>[];

  List<String> mapOf(String key) {
    final ns = namespaceOf(key);
    return [ns, subKeyOf(key, ns)];
  }

  // First pass: initial mappings.
  for (final key in keys) {
    keyMap[key] = mapOf(key);
  }
  // A flat key whose name equals a namespace name would collide with that
  // namespace's access path at the root level (`l10n.session` label vs
  // `l10n.session.*`); nest it into itself instead (`session.session`).
  final nsNames = keyMap.values.map((m) => m[0]).toSet();
  for (final key in keys) {
    if (nsNames.contains(key)) keyMap[key] = [key, key];
  }

  for (final key in keys) {
    final ns = keyMap[key]![0];
    final sub = keyMap[key]![1];
    if (ns == _defaultNs) orphans.add(key);
    final enMeta = en['@$key'] as Map<String, Object?>?;
    final enValue = _convertValue(en[key] as String, enMeta);
    final zhValue = _convertValue(zh[key] as String, enMeta);
    files.putIfAbsent(ns, () => {})[sub + enValue.jsonKey] = enValue.value;
    filesZh.putIfAbsent(ns, () => {})[sub + zhValue.jsonKey] = zhValue.value;
    keyMap[key] = [ns, sub];

    final description = enMeta?['description'] as String?;
    if (description != null && description.isNotEmpty) {
      files[ns]!['@$sub'] = description;
      filesZh[ns]!['@$sub'] = description;
    }
  }

  // Collision check: two keys mapping to the same ns+subKey.
  final seen = <String, String>{};
  for (final entry in keyMap.entries) {
    final path = '${entry.value[0]}.${entry.value[1]}';
    if (seen.containsKey(path)) {
      stderr.writeln('COLLISION: $path from ${seen[path]} and ${entry.key}');
      exit(1);
    }
    seen[path] = entry.key;
  }

  final report = StringBuffer()
    ..writeln('# l10n namespace split report')
    ..writeln()
    ..writeln('| namespace | keys |')
    ..writeln('|---|---|');
  final sortedNs = files.keys.toList()..sort();
  for (final ns in sortedNs) {
    final count = files[ns]!.keys.where((k) => !k.startsWith('@')).length;
    report.writeln('| $ns | $count |');
  }
  report
    ..writeln()
    ..writeln('## `_default` keys (${orphans.length})')
    ..writeln()
    ..writeln(orphans.join('\n'));

  if (!dryRun) {
    Directory('lib/i18n').createSync(recursive: true);
    for (final ns in sortedNs) {
      File(
        'lib/i18n/${ns == _defaultNs ? '_default' : ns}_en.i18n.json',
      ).writeAsStringSync(_prettyJson(files[ns]!));
      File(
        'lib/i18n/${ns == _defaultNs ? '_default' : ns}_zh.i18n.json',
      ).writeAsStringSync(_prettyJson(filesZh[ns]!));
    }
    File(
      'tool/l10n_key_map.json',
    ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(keyMap));
    File('tool/l10n_migration_report.md').writeAsStringSync(report.toString());
  }

  stdout.writeln(
    'Namespaces: ${sortedNs.length}, keys: ${keys.length}, '
    'orphans: ${orphans.length}${dryRun ? ' (dry run)' : ''}',
  );
}

String _firstWord(String key) => key.startsWith(RegExp(r'^[a-z]+'))
    ? RegExp(r'^[a-z]+').firstMatch(key)!.group(0)!
    : key;

Map<String, Object?> _loadArb(String path) =>
    jsonDecode(File(path).readAsStringSync()) as Map<String, Object?>;

/// Converts an ARB ICU value into a slang JSON value (String, or a plural
/// node map like `{"one": ..., "other": ...}`).
({String jsonKey, Object? value}) _convertValue(
  String value,
  Map<String, Object?>? meta,
) {
  final plural = _parseIcuPlural(value);
  if (plural != null) {
    final (param, branches) = plural;
    final node = <String, Object?>{};
    branches.forEach((quantity, branchValue) {
      node[quantity] = _typePlaceholders(branchValue, meta, forceInt: param);
    });
    return (jsonKey: '(param=$param)', value: node);
  }
  return (jsonKey: '', value: _typePlaceholders(value, meta));
}

String _prettyJson(Map<String, Object?> map) {
  final out = StringBuffer('{\n');
  final entries = map.entries.toList();
  for (var i = 0; i < entries.length; i++) {
    final e = entries[i];
    final value = e.value is String
        ? jsonEncode(e.value)
        : const JsonEncoder.withIndent('  ').convert(e.value);
    final comma = i == entries.length - 1 ? '' : ',';
    out.writeln('  ${jsonEncode(e.key)}: $value$comma');
  }
  out.writeln('}');
  return out.toString();
}

/// Replaces `{p}` with typed `{p: int}` / `{p: String}` based on ARB metadata.
String _typePlaceholders(
  String value,
  Map<String, Object?>? meta, {
  String? forceInt,
}) {
  final placeholders = meta?['placeholders'] as Map<String, Object?>?;
  return value.replaceAllMapped(RegExp(r'\{(\w+)\}'), (m) {
    final p = m.group(1)!;
    if (p == forceInt) return '{$p: int}';
    final type = placeholders?[p] is Map
        ? ((placeholders![p] as Map)['type'] as String?)
        : null;
    if (type == 'int' || type == 'num' || type == 'double') {
      return '{$p: $type}';
    }
    if (type == 'String') return '{$p: String}';
    return '{$p}';
  });
}

/// Parses `{count, plural, one{...} other{...}}`; returns (param, branches).
(String, Map<String, String>)? _parseIcuPlural(String value) {
  final m = RegExp(r'^\{(\w+),\s*plural,\s*(.+)\}$').firstMatch(value);
  if (m == null) return null;
  final branches = <String, String>{};
  final content = m.group(2)!;
  final branchRegex = RegExp(r'((?:=|\w)+) *\{((?:[^}{]+|\{[^}]+\})+)\}');
  for (final match in branchRegex.allMatches(content)) {
    var quantity = match.group(1)!;
    if (quantity.startsWith('=')) {
      quantity = switch (quantity.substring(1)) {
        '0' => 'zero',
        '1' => 'one',
        '2' => 'two',
        final n => 'other_$n',
      };
    }
    branches[quantity] = match.group(2)!;
  }
  return (m.group(1)!, branches);
}
