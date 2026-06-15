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
const _targetMappingFile = 'lib/utils/file_icon_mapping.g.dart';

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
  final packResult = await Process.run('npm', ['pack', _packageName], workingDirectory: temp.path);
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
  final extractResult = await Process.run(
    'tar',
    ['-xzf', tgzFiles.first.path, '-C', temp.path],
    runInShell: true,
  );
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

/// Collects the set of icon names referenced by the mapping (from iconDefinitions
/// plus every extension/fileName/languageId value), preserving order by insertion.
Set<String> _collectReferencedIconNames(Map<String, dynamic> json) {
  final names = <String>{};
  void addFromMap(Object? map) {
    if (map is Map) {
      for (final v in map.values) {
        if (v is String) names.add(v);
      }
    }
  }

  // iconDefinitions keys are the icon names themselves.
  final defs = json['iconDefinitions'];
  if (defs is Map) {
    names.addAll(defs.keys.cast<String>());
  }
  addFromMap(json['fileExtensions']);
  addFromMap(json['fileNames']);
  addFromMap(json['languageIds']);
  // Default folder/file icons referenced at top level.
  for (final k in const ['file', 'folder', 'folderExpanded', 'rootFolder', 'rootFolderExpanded']) {
    final v = json[k];
    if (v is String) names.add(v);
  }
  return names;
}

/// Copies referenced SVGs from <pkg>/icons into the target dir.
/// Returns (copiedCount, missingNames) where missingNames are referenced but
/// absent in the source (treated as non-fatal warnings).
({int copied, List<String> missing}) _copySvgs({
  required Directory pkgDir,
  required Directory targetDir,
  required Set<String> referencedNames,
}) {
  final srcIcons = Directory('${pkgDir.path}/icons');
  if (!srcIcons.existsSync()) {
    stderr.writeln('Source icons/ dir not found at ${srcIcons.path}');
    exit(1);
  }
  // Wipe target so removed icons don't linger.
  if (targetDir.existsSync()) {
    targetDir.deleteSync(recursive: true);
  }
  targetDir.createSync(recursive: true);

  var copied = 0;
  final missing = <String>[];
  final sortedNames = referencedNames.toList()..sort();
  for (final name in sortedNames) {
    final src = File('${srcIcons.path}/$name.svg');
    if (src.existsSync()) {
      final dst = File('${targetDir.path}/$name.svg');
      dst.writeAsBytesSync(src.readAsBytesSync());
      copied++;
    } else {
      missing.add(name);
    }
  }
  return (copied: copied, missing: missing);
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
  final json = jsonDecode(mappingFile.readAsStringSync()) as Map<String, dynamic>;

  final referenced = _collectReferencedIconNames(json);
  print('Referenced icon names: ${referenced.length}');

  final targetDir = Directory(_targetSvgDir);
  final (:copied, :missing) = _copySvgs(
    pkgDir: pkgDir,
    targetDir: targetDir,
    referencedNames: referenced,
  );
  print('Copied $copied SVGs into $_targetSvgDir/.');
  if (missing.isNotEmpty) {
    print('WARNING: ${missing.length} referenced icons missing in source: $missing');
  }
  if (force) print('(force: version cache check skipped)');

  print('SVG sync done. (mapping generation not yet implemented)');
}
