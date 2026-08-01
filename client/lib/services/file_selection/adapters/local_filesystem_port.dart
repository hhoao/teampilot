import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shared_ui/shared_ui.dart';

/// Local [dart:io] filesystem browsing for [TpFileSelection].
class LocalFilesystemPort implements TpFilesystemPort {
  const LocalFilesystemPort();

  static const _androidStorageRoot = '/storage/emulated/0';
  static const _androidDownloadsRoot = '/storage/emulated/0/Download';

  @override
  List<TpFilesystemRoot> defaultRoots() {
    if (Platform.isAndroid) {
      return const [
        TpFilesystemRoot(
          id: 'phone_storage',
          label: 'Phone storage',
          path: _androidStorageRoot,
        ),
        TpFilesystemRoot(
          id: 'downloads',
          label: 'Downloads',
          path: _androidDownloadsRoot,
        ),
      ];
    }

    final home = Platform.environment['HOME'] ?? '/';
    return [
      TpFilesystemRoot(id: 'home', label: 'Home', path: home),
    ];
  }

  @override
  String defaultBrowsePath() {
    if (Platform.isAndroid) return _androidStorageRoot;
    return Platform.environment['HOME'] ?? '/';
  }

  @override
  Future<List<TpFsEntry>> listDir(String path) async {
    final dir = Directory(path);
    if (!await dir.exists()) {
      return const [];
    }

    final entities = await dir.list(followLinks: false).toList();
    final entries = <TpFsEntry>[];
    for (final entity in entities) {
      final stat = await entity.stat();
      final kind = switch (entity) {
        Directory() => TpFsEntryKind.directory,
        File() => TpFsEntryKind.file,
        _ => TpFsEntryKind.other,
      };
      entries.add(
        TpFsEntry(
          path: entity.path,
          name: p.basename(entity.path),
          kind: kind,
          modifiedAt: stat.modified,
          sizeBytes: kind == TpFsEntryKind.file ? stat.size : null,
        ),
      );
    }
    return entries;
  }

  @override
  Future<List<TpFsEntry>>? Function(String rootPath, String query)?
      get searchFiles => null;

  @override
  Future<bool> exists(String path) async {
    return FileSystemEntity.typeSync(path) != FileSystemEntityType.notFound;
  }

  @override
  Future<TpFsEntryKind> kindOf(String path) async {
    return switch (FileSystemEntity.typeSync(path)) {
      FileSystemEntityType.directory => TpFsEntryKind.directory,
      FileSystemEntityType.file => TpFsEntryKind.file,
      _ => TpFsEntryKind.other,
    };
  }
}
