import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Zero-compat guard: the P1 cleanup removed the legacy runtime surface. These
/// assertions fail loudly if a scaffold token reappears.
void main() {
  String read(String path) => File(path).readAsStringSync();

  Iterable<File> libDartFiles() => Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'));

  test('storage singleton + StorageRoots are gone repo-wide (P2)', () {
    for (final f in libDartFiles()) {
      final src = f.readAsStringSync();
      expect(
        src.contains('RuntimeStorageContext'),
        isFalse,
        reason: '${f.path} still references RuntimeStorageContext',
      );
      expect(
        RegExp(r'\bStorageRoots\b').hasMatch(src),
        isFalse,
        reason: '${f.path} still references StorageRoots',
      );
    }
  });

  test('legacy folders reader is gone repo-wide', () {
    for (final f in libDartFiles()) {
      expect(
        f.readAsStringSync().contains('foldersFromLegacyJson'),
        isFalse,
        reason: '${f.path} still references foldersFromLegacyJson',
      );
    }
  });

  test('dead connection-mode toggle constant is gone', () {
    for (final f in libDartFiles()) {
      expect(
        f.readAsStringSync().contains('kShowConnectionModeSetting'),
        isFalse,
        reason: '${f.path} still references kShowConnectionModeSetting',
      );
    }
  });

  test('SessionPreferences carries no legacy runtime knobs', () {
    final src = read('lib/models/session_preferences.dart');
    expect(src.contains('connectionMode'), isFalse);
    expect(src.contains('windowsStorageBackend'), isFalse);
  });

  test('targets registry has no migrate/default authority', () {
    final src = read('lib/services/storage/runtime_target_registry.dart');
    expect(src.contains('migrateIfNeeded'), isFalse);
    expect(src.contains('defaultTargetId'), isFalse);
    expect(src.contains('setDefaultTargetId'), isFalse);
  });

  test('app_shell has no legacy target synthesis helpers', () {
    final src = read('lib/app/app_shell.dart');
    expect(src.contains('currentLegacyTargetId'), isFalse);
    expect(src.contains('synthTarget'), isFalse);
  });

  test('models write no primaryPath/additionalPaths dual-write', () {
    for (final p in [
      'lib/models/workspace.dart',
      'lib/models/app_session.dart',
    ]) {
      final src = read(p);
      expect(src.contains("'primaryPath'"), isFalse, reason: p);
      expect(src.contains("'additionalPaths'"), isFalse, reason: p);
    }
  });
}
