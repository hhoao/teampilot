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

Future<void> main(List<String> args) async {
  final force = args.contains('--force');
  final pkgDir = await _prepareNpmPackage(args);
  print('Using npm package at: ${pkgDir.path}');

  final mappingFile = File('${pkgDir.path}/dist/material-icons.json');
  if (!mappingFile.existsSync()) {
    stderr.writeln('material-icons.json not found at ${mappingFile.path}');
    exit(1);
  }
  final json = jsonDecode(mappingFile.readAsStringSync()) as Map<String, dynamic>;
  print('material-icons.json top keys: ${json.keys.toList()}');

  print('Skeleton OK. version json loaded with ${json.length} top keys. force=$force');
}
