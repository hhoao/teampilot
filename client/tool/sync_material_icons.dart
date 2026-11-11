// ignore_for_file: avoid_print
//
// Syncs VSCode Material Icon Theme SVGs + mapping into this repo. Run from `client/`:
//
//   dart run tool/sync_material_icons.dart
//
// By default it downloads material-icon-theme npm package to a temp dir.
// Use --npm-package <path> to point at a pre-extracted package directory.
// Use --force to skip the version cache check.

import 'dart:convert';
import 'dart:io';

const _packageName = 'material-icon-theme';
const _targetSvgDir = 'assets/file_icons';
const _targetMappingFile = 'lib/utils/ui/file_icon_mapping.g.dart';

Future<Directory> _prepareNpmPackage(List<String> args) async {
  final pkgArgIdx = args.indexOf('--npm-package');
  if (pkgArgIdx >= 0 && pkgArgIdx + 1 < args.length) {
    final dir = Directory(args[pkgArgIdx + 1]);
    if (!dir.existsSync()) {
      stderr.writeln('--npm-package dir does not exist: ${dir.path}');
      exit(1);
    }
    return dir;
  }
  // Default: download via `npm pack` into a temp dir and extract.
  final temp = await Directory.systemTemp.createTemp('material-icon-theme-');
  print('Downloading $_packageName via npm pack into ${temp.path} ...');
  final packResult = await Process.run(
    'npm',
    ['pack', _packageName],
    workingDirectory: temp.path,
    runInShell: true,
  );
  if (packResult.exitCode != 0) {
    stderr.writeln('npm pack failed:\n${packResult.stderr}');
    exit(1);
  }
  final tgzFiles = temp
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.tgz'))
      .toList();
  if (tgzFiles.isEmpty) {
    stderr.writeln('No .tgz produced by npm pack.');
    exit(1);
  }
  final tgzPath = tgzFiles.first.path;
  final extractResult = await Process.run('tar', [
    '-xzf',
    tgzPath,
    '-C',
    temp.path,
    '--force-local',
  ], runInShell: true);
  if (extractResult.exitCode != 0) {
    stderr.writeln('tar extract failed:\n${extractResult.stderr}');
    exit(1);
  }
  // npm pack extracts into ./package/
  final pkgDir = Directory('${temp.path}/package');
  if (!pkgDir.existsSync()) {
    stderr.writeln('Extracted package/ dir not found at ${pkgDir.path}');
    exit(1);
  }
  return pkgDir;
}

/// Reads the npm package version from its package.json.
String _readPackageVersion(Directory pkgDir) {
  final pkgJson = File('${pkgDir.path}/package.json');
  if (!pkgJson.existsSync()) return 'unknown';
  final data = jsonDecode(pkgJson.readAsStringSync()) as Map<String, dynamic>;
  return (data['version'] ?? 'unknown').toString();
}

/// Maps every icon name the generated mapping can reference to its source SVG.
///
/// Names are collected from the icon maps at the top level and under `light`:
/// the runtime appends `_light` to a base icon on light themes, so those
/// definitions must be bundled as well. A definition's [iconPath] is
/// authoritative — some point at `<name>.clone.svg`, so the file is not always
/// named after the icon. Exits when any name has no source file.
Map<String, String> _resolveIconSources(
  Map<String, dynamic> json,
  Directory pkgDir,
) {
  final defs = json['iconDefinitions'];
  final names = <String>{};

  void addFromMaps(Object? section) {
    if (section is! Map) return;
    for (final key in const [
      'fileExtensions',
      'fileNames',
      'languageIds',
      'folderNames',
      'folderNamesExpanded',
    ]) {
      final map = section[key];
      if (map is! Map) continue;
      for (final v in map.values) {
        if (v is String) names.add(v);
      }
    }
  }

  addFromMaps(json);
  addFromMaps(json['light']);
  for (final k in const [
    'file',
    'folder',
    'folderExpanded',
    'rootFolder',
    'rootFolderExpanded',
  ]) {
    final v = json[k];
    if (v is String) names.add(v);
  }

  if (defs is! Map) {
    stderr.writeln('material-icons.json has no iconDefinitions.');
    exit(1);
  }
  final distDir = Directory('${pkgDir.path}/dist');
  final sources = <String, String>{};
  final unresolved = <String>[];
  for (final name in names) {
    final def = defs[name];
    final iconPath = def is Map ? def['iconPath'] : null;
    if (iconPath is! String) {
      unresolved.add(name);
      continue;
    }
    final src = File.fromUri(distDir.uri.resolve(iconPath));
    if (!src.existsSync()) {
      unresolved.add(name);
      continue;
    }
    sources[name] = src.path;
  }
  if (unresolved.isNotEmpty) {
    stderr.writeln(
      'FATAL: ${unresolved.length} icons referenced by '
      'material-icons.json have no source SVG: '
      '${unresolved.take(20).toList()}',
    );
    exit(1);
  }
  return sources;
}

/// Copies each resolved source SVG into [targetDir] as `<name>.svg`.
int _copySvgs({
  required Directory targetDir,
  required Map<String, String> sources,
}) {
  // Wipe target so removed icons don't linger.
  if (targetDir.existsSync()) {
    targetDir.deleteSync(recursive: true);
  }
  targetDir.createSync(recursive: true);

  final names = sources.keys.toList()..sort();
  for (final name in names) {
    File(sources[name]!).copySync('${targetDir.path}/$name.svg');
  }
  return names.length;
}

/// Writes lib/utils/ui/file_icon_mapping.g.dart with sorted const maps.
void _writeMappingFile({
  required String version,
  required Map<String, dynamic> json,
}) {
  String dartStringLiteral(String s) {
    // Escape backslash and single quote.
    final escaped = s.replaceAll(r'\', r'\\').replaceAll("'", r"\'");
    return "'$escaped'";
  }

  void writeMap(String varName, Map<String, String> m, StringSink out) {
    final sortedKeys = m.keys.toList()..sort();
    out.writeln('const Map<String, String> $varName = {');
    for (final k in sortedKeys) {
      out.writeln('  ${dartStringLiteral(k)}: ${dartStringLiteral(m[k]!)},');
    }
    out.writeln('};');
    out.writeln();
  }

  void writeSet(String varName, Iterable<String> values, StringSink out) {
    final sorted = values.toList()..sort();
    out.writeln('const Set<String> $varName = {');
    for (final v in sorted) {
      out.writeln('  ${dartStringLiteral(v)},');
    }
    out.writeln('};');
    out.writeln();
  }

  Map<String, String> castMap(Object? m) {
    if (m is! Map) return {};
    return m.map((k, v) => MapEntry(k.toString(), v.toString()));
  }

  final extMap = castMap(json['fileExtensions']);
  final nameMap = castMap(json['fileNames']);
  final light = json['light'];
  final lightExt = light is Map
      ? castMap(light['fileExtensions']).keys.toSet()
      : <String>{};
  final lightName = light is Map
      ? castMap(light['fileNames']).keys.toSet()
      : <String>{};
  final defaultIcon = (json['file'] ?? 'file').toString();

  final buf = StringBuffer()
    ..writeln('// GENERATED BY tool/sync_material_icons.dart — DO NOT EDIT.')
    ..writeln('// Source: material-icon-theme@$version (MIT)')
    ..writeln()
    ..writeln('const materialFileIconsVersion = ${dartStringLiteral(version)};')
    ..writeln()
    ..writeln(
      'const String kDefaultFileIcon = ${dartStringLiteral(defaultIcon)};',
    )
    ..writeln();
  writeMap('kFileExtensionIcons', extMap, buf);
  writeMap('kFileNameIcons', nameMap, buf);
  writeSet('kLightFileExtensions', lightExt, buf);
  writeSet('kLightFileNames', lightName, buf);

  File(_targetMappingFile).writeAsStringSync(buf.toString());
  print(
    'Wrote $_targetMappingFile '
    '(extensions=${extMap.length}, fileNames=${nameMap.length}, '
    'lightExt=${lightExt.length}, lightName=${lightName.length}).',
  );
}

Future<void> main(List<String> args) async {
  final force = args.contains('--force');
  final pkgDir = await _prepareNpmPackage(args);
  final version = _readPackageVersion(pkgDir);
  print('Using $_packageName@$version at: ${pkgDir.path}');

  final mappingFile = File('${pkgDir.path}/dist/material-icons.json');
  if (!mappingFile.existsSync()) {
    stderr.writeln('material-icons.json not found at ${mappingFile.path}');
    exit(1);
  }
  final json =
      jsonDecode(mappingFile.readAsStringSync()) as Map<String, dynamic>;

  final sources = _resolveIconSources(json, pkgDir);
  print('Referenced icon names: ${sources.length}');

  final targetDir = Directory(_targetSvgDir);
  final copied = _copySvgs(targetDir: targetDir, sources: sources);
  print('Copied $copied SVGs into $_targetSvgDir/.');
  if (force) print('(force: version cache check skipped)');

  _writeMappingFile(version: version, json: json);

  print('Done. material-icon-theme@$version synced.');
}
