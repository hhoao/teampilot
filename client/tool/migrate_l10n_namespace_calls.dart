// One-off migration tool (phase 2): rewrite flat l10n access paths to
// namespace access paths using tool/l10n_key_map.json produced by
// tool/migrate_l10n_namespaces.dart.
//
// Usage: cd client && dart run tool/migrate_l10n_namespace_calls.dart [--dry-run]
//
// `l10n.chatComposeSend` -> `l10n.chat.composeSend`
// Keys mapped to the `_default` namespace keep their root access path and are
// skipped. Keys are processed longest-first with a camelCase-boundary lookahead
// so `chatComposeSendX` never matches `chatComposeSend`.

import 'dart:convert';
import 'dart:io';

const _skipPaths = <String>{
  'lib/l10n/l10n_extensions.dart',
  'lib/l10n/l10n_compat.dart',
  'lib/l10n/app_localizations.dart',
};

void main(List<String> args) {
  final dryRun = args.contains('--dry-run');
  final qualifyMode = args.contains('--qualify');
  final root = Directory.current.path;
  final keyMap =
      jsonDecode(File('$root/tool/l10n_key_map.json').readAsStringSync())
          as Map<String, dynamic>;

  // flat key -> "ns.sub"; longest keys first.
  final entries =
      keyMap.entries
          .where((e) => (e.value as List).first != '_default')
          .map(
            (e) => MapEntry(
              e.key,
              '${(e.value as List).first}.${(e.value as List).last}',
            ),
          )
          .toList()
        ..sort((a, b) => b.key.length.compareTo(a.key.length));

  final patterns = entries.map((e) {
    final escaped = e.key.replaceAll(r'\', r'\\');
    final RegExp pattern;
    if (qualifyMode) {
      // Bare identifier (implicit `this` receiver inside the extension file):
      // not preceded by `.`/word char, camelCase-boundary lookahead.
      pattern = RegExp('(?<![.\\w])$escaped(?![A-Za-z0-9_])');
    } else {
      pattern = RegExp('l10n\\s*\\.\\s*$escaped(?![A-Za-z0-9_])');
    }
    return (e.key, pattern, e.value);
  }).toList();

  if (qualifyMode) {
    _qualifyFile(File('$root/lib/l10n/l10n_extensions.dart'), patterns, dryRun);
    return;
  }

  var filesChanged = 0;
  var sites = 0;
  for (final dir in ['lib', 'test']) {
    for (final entity in Directory('$root/$dir').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final rel = entity.path.substring(root.length + 1);
      if (rel.endsWith('.g.dart') || _skipPaths.contains(rel)) continue;
      var src = entity.readAsStringSync();
      final before = src;
      var siteCount = 0;
      for (final (key, pattern, target) in patterns) {
        src = src.replaceAllMapped(pattern, (m) {
          siteCount++;
          // Match always ends at the end of the flat key; preserve the
          // receiver part (`l10n`, `_l10n`, whitespace, dot).
          final matchText = m.group(0)!;
          final receiverEnd = matchText.length - key.length;
          return '${matchText.substring(0, receiverEnd)}$target';
        });
      }
      if (src != before) {
        filesChanged++;
        sites += siteCount;
        stdout.writeln('$rel: $siteCount');
        if (!dryRun) entity.writeAsStringSync(src);
      }
    }
  }
  stdout.writeln(
    'Files changed: $filesChanged, sites: $sites${dryRun ? ' (dry run)' : ''}',
  );
}

void _qualifyFile(
  File file,
  List<(String, RegExp, String)> patterns,
  bool dryRun,
) {
  var src = file.readAsStringSync();
  var siteCount = 0;
  for (final (key, pattern, target) in patterns) {
    src = src.replaceAllMapped(pattern, (m) {
      siteCount++;
      return target;
    });
  }
  stdout.writeln(
    'qualify l10n_extensions.dart: $siteCount sites${dryRun ? ' (dry run)' : ''}',
  );
  if (!dryRun && src.isNotEmpty) file.writeAsStringSync(src);
}
