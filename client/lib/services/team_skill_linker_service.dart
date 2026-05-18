import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/skill.dart';
import '../utils/logger.dart';
import 'app_storage.dart';
import 'flashskyai_storage_roots.dart';

class TeamSkillSyncResult {
  const TeamSkillSyncResult({
    this.linked = const [],
    this.skippedMissingIds = const [],
    this.errors = const [],
  });

  final List<String> linked;
  final List<String> skippedMissingIds;
  final List<String> errors;

  bool get ok => errors.isEmpty;
}

class TeamSkillLinkerService {
  TeamSkillLinkerService({
    String? appSkillsRoot,
    String? cliSkillsDir,
    bool? useWslSymlinks,
    FlashskyaiStorageRoots? storageRoots,
  }) : _appSkillsRoot = appSkillsRoot,
       _cliSkillsDirOverride = cliSkillsDir,
       _useWslSymlinks = useWslSymlinks,
       _storageRoots = storageRoots;

  final String? _appSkillsRoot;
  final String? _cliSkillsDirOverride;
  final bool? _useWslSymlinks;
  final FlashskyaiStorageRoots? _storageRoots;

  String get appSkillsDir =>
      _appSkillsRoot ?? p.join(AppStorage.basePath, 'skills');

  String get cliSkillsDir =>
      _cliSkillsDirOverride ?? p.join(AppStorage.flashskyaiDataDir, 'skills');

  String sourceDirFor(Skill skill) => p.join(appSkillsDir, skill.directory);

  bool get _shouldUseWsl {
    if (_useWslSymlinks != null) return _useWslSymlinks;
    if (!Platform.isWindows) return false;
    return AppStorage.flashskyaiDataDir.contains(r'\') ||
        AppStorage.flashskyaiDataDir.contains(':');
  }

  Future<TeamSkillSyncResult> syncForTeam({
    required List<String> skillIds,
    required List<Skill> installed,
  }) async {
    final byId = {for (final s in installed) s.id: s};
    final toLink = <Skill>[];
    final skipped = <String>[];

    for (final id in skillIds) {
      final skill = byId[id];
      if (skill == null) {
        skipped.add(id);
        continue;
      }
      toLink.add(skill);
    }

    final roots = await _storageRoots?.resolve();
    if (roots != null &&
        roots.storageIsRemote &&
        roots.remoteFileStore != null) {
      return _syncRemoteSymlinks(roots, toLink, skipped);
    }

    if (_shouldUseWsl) {
      return _syncViaWsl(toLink, skipped);
    }
    return _syncNative(toLink, skipped);
  }

  /// Links remote teampilot/skills → ~/.flashskyai/skills (same as desktop).
  Future<TeamSkillSyncResult> _syncRemoteSymlinks(
    StorageRootsSnapshot roots,
    List<Skill> toLink,
    List<String> skipped,
  ) async {
    final store = roots.remoteFileStore!;
    final posix = p.Context(style: p.Style.posix);
    final errors = <String>[];
    final linked = <String>[];

    try {
      await store.ensureDirectory(roots.cliSkillsDir);
      final entries = await store.listDirectoryEntries(roots.cliSkillsDir);
      for (final entry in entries) {
        await store.removeRecursive(posix.join(roots.cliSkillsDir, entry.name));
      }
    } catch (e) {
      return TeamSkillSyncResult(
        skippedMissingIds: skipped,
        errors: ['Failed to clear remote CLI skills dir: $e'],
      );
    }

    for (final skill in toLink) {
      final source = posix.join(roots.skillsRoot, skill.directory);
      final target = posix.join(roots.cliSkillsDir, skill.directory);
      try {
        if (!await store.fileExists(posix.join(source, 'SKILL.md'))) {
          errors.add('${skill.name}: source missing at $source');
          continue;
        }
        await store.createSymlink(target: source, linkPath: target);
        linked.add(skill.directory);
      } catch (e) {
        errors.add('${skill.name}: $e');
        appLogger.w('[team-skills] remote link failed for ${skill.id}: $e');
      }
    }

    return TeamSkillSyncResult(
      linked: linked,
      skippedMissingIds: skipped,
      errors: errors,
    );
  }

  Future<TeamSkillSyncResult> _syncNative(
    List<Skill> toLink,
    List<String> skipped,
  ) async {
    final errors = <String>[];
    final linked = <String>[];

    // Android local-PTY has no CLI — symlinks would serve no purpose and may
    // fail on filesystems that don't support them (e.g. sdcardfs).
    if (Platform.isAndroid) {
      return TeamSkillSyncResult(
        linked: toLink.map((s) => s.directory).toList(),
        skippedMissingIds: skipped,
      );
    }

    try {
      await _clearCliSkillsDir();
    } catch (e) {
      return TeamSkillSyncResult(
        skippedMissingIds: skipped,
        errors: ['Failed to clear skills dir: $e'],
      );
    }

    for (final skill in toLink) {
      final source = sourceDirFor(skill);
      final target = p.join(cliSkillsDir, skill.directory);
      try {
        await _createDirectoryLink(source: source, target: target);
        linked.add(skill.directory);
      } catch (e) {
        errors.add('${skill.name}: $e');
        appLogger.w('[team-skills] link failed for ${skill.id}: $e');
      }
    }

    return TeamSkillSyncResult(
      linked: linked,
      skippedMissingIds: skipped,
      errors: errors,
    );
  }

  Future<TeamSkillSyncResult> _syncViaWsl(
    List<Skill> toLink,
    List<String> skipped,
  ) async {
    final errors = <String>[];
    final linked = <String>[];

    final wslCliDir = await _windowsPathToWsl(cliSkillsDir);
    if (wslCliDir == null) {
      return TeamSkillSyncResult(
        skippedMissingIds: skipped,
        errors: ['Could not resolve WSL path for CLI skills directory'],
      );
    }

    await _wslRun(['rm', '-rf', '$wslCliDir/*'], ignoreErrors: true);
    await _wslRun(['mkdir', '-p', wslCliDir]);

    for (final skill in toLink) {
      final source = sourceDirFor(skill);
      if (!Directory(source).existsSync()) {
        errors.add('${skill.name}: source missing at $source');
        continue;
      }
      final wslSource = await _windowsPathToWsl(source);
      if (wslSource == null) {
        errors.add('${skill.name}: could not resolve WSL source path');
        continue;
      }
      final wslTarget = '$wslCliDir/${skill.directory}';
      final result = await _wslRun(['ln', '-sf', wslSource, wslTarget]);
      if (result.exitCode != 0) {
        final msg = (result.stderr as String?)?.trim() ?? 'ln failed';
        errors.add('${skill.name}: $msg');
      } else {
        linked.add(skill.directory);
      }
    }

    return TeamSkillSyncResult(
      linked: linked,
      skippedMissingIds: skipped,
      errors: errors,
    );
  }

  Future<void> _clearCliSkillsDir() async {
    final dir = Directory(cliSkillsDir);
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
      return;
    }
    for (final entity in dir.listSync(followLinks: false)) {
      await _deleteEntity(entity);
    }
  }

  Future<void> _deleteEntity(FileSystemEntity entity) async {
    if (entity is Directory) {
      await entity.delete(recursive: true);
    } else if (entity is File || entity is Link) {
      await entity.delete();
    }
  }

  Future<void> _createDirectoryLink({
    required String source,
    required String target,
  }) async {
    final srcDir = Directory(source);
    if (!srcDir.existsSync()) {
      throw StateError('source directory missing: $source');
    }

    final targetLink = Link(target);
    if (targetLink.existsSync()) {
      await targetLink.delete();
    }
    final targetDir = Directory(target);
    if (targetDir.existsSync()) {
      await targetDir.delete(recursive: true);
    }

    try {
      await Link(target).create(source);
    } on FileSystemException catch (e) {
      if (!Platform.isWindows) rethrow;
      final result = await Process.run('cmd', [
        '/c',
        'mklink',
        '/J',
        target,
        source,
      ]);
      if (result.exitCode != 0) {
        throw FileSystemException('junction failed', target, e.osError);
      }
    }
  }

  Future<String?> _windowsPathToWsl(String windowsPath) async {
    final result = await Process.run('wsl.exe', ['wslpath', '-u', windowsPath]);
    if (result.exitCode != 0) return null;
    final out = (result.stdout as String?)?.trim() ?? '';
    return out.isEmpty ? null : out;
  }

  Future<ProcessResult> _wslRun(
    List<String> args, {
    bool ignoreErrors = false,
  }) async {
    final result = await Process.run('wsl.exe', args);
    if (!ignoreErrors && result.exitCode != 0) {
      appLogger.w('[team-skills] wsl ${args.join(' ')}: ${result.stderr}');
    }
    return result;
  }
}
