import 'dart:io';

import '../../models/discoverable_team.dart';
import '../../models/skill.dart';
import '../../models/skill_acquire_spec.dart';
import '../../models/skill_pack.dart';
import '../cli/installer_types.dart';
import '../storage/app_storage.dart';
import 'skill_install_service.dart';
import 'skill_manifest_service.dart';
import 'skill_pack_registry.dart';

typedef SkillInstallRunner =
    Future<CliInstallerCommandResult> Function(CliInstallerCommand command);

typedef SkillGitDirInstaller =
    Future<Skill> Function(
      DiscoverableSkill discovery, {
      bool overwrite,
      String? idOverride,
    });

typedef SkillDirectoryRegistrar =
    Future<Skill> Function({
      required String id,
      required String directory,
    });

class SkillAcquireResult {
  const SkillAcquireResult({
    required this.success,
    this.message = '',
    this.skillId,
  });

  final bool success;
  final String message;
  final String? skillId;
}

/// Installs skills via declarative [SkillAcquireSpec] (`git-dir` default, `script`).
///
/// Desktop/local only for shell kinds in v1 — same host gate as Extension acquire.
///
/// Already-installed-by-id short-circuit lives in SkillCubit (Task 3 wiring): this
/// engine does not skip work when [SkillDependencyRef.expectedLocalId] is already
/// in the manifest. Callers that want idempotent install should pre-check by id
/// before invoking [install] / [installDiscoverable].
class SkillAcquisitionEngine {
  SkillAcquisitionEngine({
    SkillInstallRunner? runner,
    required SkillGitDirInstaller installGitDir,
    bool Function()? isLocalAcquireSupported,
    SkillDirectoryRegistrar? registerDirectory,
    Future<Set<String>> Function()? listSkillDirsWithSkillMd,
    SkillPackRegistry? packRegistry,
  }) : _runner = runner ?? _defaultLocalRunner,
       _installGitDir = installGitDir,
       _isLocalAcquireSupported =
           isLocalAcquireSupported ?? _defaultLocalAcquireSupported,
       _registerDirectory =
           registerDirectory ??
           SkillInstallService(
             manifest: SkillManifestService(),
           ).registerInstalledDirectory,
       _listSkillDirsWithSkillMd =
           listSkillDirsWithSkillMd ?? _defaultListSkillDirsWithSkillMd,
       _packRegistry = packRegistry ?? SkillPackRegistry();

  final SkillInstallRunner _runner;
  final SkillGitDirInstaller _installGitDir;
  final bool Function() _isLocalAcquireSupported;
  final SkillDirectoryRegistrar _registerDirectory;
  final Future<Set<String>> Function() _listSkillDirsWithSkillMd;
  final SkillPackRegistry _packRegistry;

  static bool _defaultLocalAcquireSupported() => true;

  static Future<CliInstallerCommandResult> _defaultLocalRunner(
    CliInstallerCommand command,
  ) async {
    try {
      final result = await Process.run(command.executable, command.arguments);
      return CliInstallerCommandResult(
        exitCode: result.exitCode,
        stdout: result.stdout?.toString() ?? '',
        stderr: result.stderr?.toString() ?? '',
      );
    } on ProcessException catch (e) {
      return CliInstallerCommandResult(exitCode: 127, stderr: e.message);
    }
  }

  static Future<Set<String>> _defaultListSkillDirsWithSkillMd() async {
    final fs = AppStorage.fs;
    final ctx = fs.pathContext;
    final skillsDir = AppPaths.skillsDirForTeampilotRoot(
      AppStorage.paths.basePath,
    );
    if (!(await fs.stat(skillsDir)).isDirectory) return {};
    final out = <String>{};
    for (final entry in await fs.listDir(skillsDir)) {
      if (!entry.isDirectory) continue;
      final skillMd = ctx.join(skillsDir, entry.name, 'SKILL.md');
      if ((await fs.stat(skillMd)).isFile) {
        out.add(entry.name);
      }
    }
    return out;
  }

  Future<SkillAcquireResult> install(
    SkillDependencyRef ref, {
    bool overwrite = false,
  }) {
    final packId = ref.packId?.trim();
    if (packId != null && packId.isNotEmpty) {
      return _installPackSkill(
        packId: packId,
        expectedLocalId: ref.expectedLocalId,
        overwrite: overwrite,
      );
    }
    return _install(
      acquire: ref.resolvedAcquire,
      discovery: ref.toDiscoverableSkill(),
      expectedLocalId: ref.expectedLocalId,
      displayName: ref.name,
      overwrite: overwrite,
    );
  }

  Future<SkillAcquireResult> installDiscoverable(
    DiscoverableSkill d, {
    bool overwrite = false,
  }) {
    final packId = d.packId?.trim();
    if (packId != null && packId.isNotEmpty) {
      return _installPackSkill(
        packId: packId,
        expectedLocalId: d.expectedLocalId,
        overwrite: overwrite,
      );
    }
    final acquire = d.acquire ?? const SkillAcquireSpec(kind: 'git-dir');
    return _install(
      acquire: acquire,
      discovery: d,
      expectedLocalId: d.expectedLocalId,
      displayName: d.name,
      overwrite: overwrite,
    );
  }

  Future<SkillAcquireResult> _installPackSkill({
    required String packId,
    required String expectedLocalId,
    required bool overwrite,
  }) async {
    final pack = _packRegistry.byId(packId);
    if (pack == null) {
      return SkillAcquireResult(
        success: false,
        message: 'Unknown skill pack: $packId',
      );
    }
    if (pack.skills.isEmpty) {
      return SkillAcquireResult(
        success: false,
        message: 'Skill pack $packId has no skills.',
      );
    }
    final entry = pack.entryById(expectedLocalId);
    if (entry == null) {
      return SkillAcquireResult(
        success: false,
        message: 'Skill $expectedLocalId is not in pack $packId.',
      );
    }

    switch (pack.acquire.kind) {
      case 'git-pack':
        return _installGitPack(
          pack: pack,
          expectedLocalId: expectedLocalId,
          overwrite: overwrite,
        );
      case 'script':
        // Opaque pack installer: run script once, then register every pack skill
        // directory that exists on disk under its pack skill id.
        final scriptResult = await _installScript(
          acquire: pack.acquire.copyWith(primaryDirectory: entry.directory),
          expectedLocalId: expectedLocalId,
          displayName: pack.name,
        );
        if (!scriptResult.success) return scriptResult;
        return _registerPackSkillsFromDisk(pack, expectedLocalId);
      default:
        return SkillAcquireResult(
          success: false,
          message: 'Unsupported pack acquire kind: ${pack.acquire.kind}',
        );
    }
  }

  Future<SkillAcquireResult> _installGitPack({
    required SkillPack pack,
    required String expectedLocalId,
    required bool overwrite,
  }) async {
    try {
      // One pack install registers every skill. Disk cache syncs the repo once;
      // already-present skill dirs are skipped so partial retries stay idempotent.
      for (final entry in pack.skills) {
        final discovery = DiscoverableSkill(
          key: entry.id,
          name: entry.name,
          description: '',
          directory: entry.directory,
          repoOwner: pack.repoOwner,
          repoName: pack.repoName,
          repoBranch: pack.repoBranch,
          id: entry.id,
          packId: pack.id,
          acquire: const SkillAcquireSpec(kind: 'git-pack'),
        );
        try {
          await _installGitDir(
            discovery,
            overwrite: overwrite,
            idOverride: entry.id,
          );
        } catch (e) {
          if (!overwrite && _isAlreadyExistsError(e)) continue;
          rethrow;
        }
      }
      return SkillAcquireResult(success: true, skillId: expectedLocalId);
    } catch (e) {
      return SkillAcquireResult(success: false, message: e.toString());
    }
  }

  static bool _isAlreadyExistsError(Object e) =>
      e.toString().toLowerCase().contains('already exists');

  Future<SkillAcquireResult> _registerPackSkillsFromDisk(
    SkillPack pack,
    String expectedLocalId,
  ) async {
    try {
      final present = await _listSkillDirsWithSkillMd();
      for (final entry in pack.skills) {
        if (!present.contains(entry.directory)) continue;
        await _registerDirectory(id: entry.id, directory: entry.directory);
      }
      if (!present.contains(
        pack.entryById(expectedLocalId)?.directory ?? '',
      )) {
        return SkillAcquireResult(
          success: false,
          message:
              'Pack install finished but ${pack.entryById(expectedLocalId)?.directory} was not found under skills/installed/.',
        );
      }
      return SkillAcquireResult(success: true, skillId: expectedLocalId);
    } catch (e) {
      return SkillAcquireResult(success: false, message: e.toString());
    }
  }

  Future<SkillAcquireResult> _install({
    required SkillAcquireSpec acquire,
    required DiscoverableSkill discovery,
    required String expectedLocalId,
    required String displayName,
    required bool overwrite,
  }) async {
    switch (acquire.kind) {
      case 'git-dir':
        try {
          final skill = await _installGitDir(
            discovery,
            overwrite: overwrite,
            idOverride: discovery.id,
          );
          return SkillAcquireResult(success: true, skillId: skill.id);
        } catch (e) {
          return SkillAcquireResult(success: false, message: e.toString());
        }
      case 'git-pack':
        final packId = discovery.packId?.trim();
        if (packId == null || packId.isEmpty) {
          return const SkillAcquireResult(
            success: false,
            message: 'git-pack acquire requires packId.',
          );
        }
        return _installPackSkill(
          packId: packId,
          expectedLocalId: expectedLocalId,
          overwrite: overwrite,
        );
      case 'script':
        return _installScript(
          acquire: acquire,
          expectedLocalId: expectedLocalId,
          displayName: displayName,
        );
      default:
        return SkillAcquireResult(
          success: false,
          message: 'Unknown skill acquire kind: ${acquire.kind}',
        );
    }
  }

  Future<SkillAcquireResult> _installScript({
    required SkillAcquireSpec acquire,
    required String expectedLocalId,
    required String displayName,
  }) async {
    if (!_isLocalAcquireSupported()) {
      return const SkillAcquireResult(
        success: false,
        message: 'Script skill install is not supported on this host.',
      );
    }

    final commands = _installCommands(acquire);
    if (commands.isEmpty) {
      return const SkillAcquireResult(
        success: false,
        message: 'No installable script target for this skill.',
      );
    }

    final before = await _listSkillDirsWithSkillMd();
    CliInstallerCommandResult? last;
    var ranOk = false;
    for (final command in commands) {
      last = await _runner(command);
      if (last.exitCode == 0) {
        ranOk = true;
        break;
      }
    }
    if (!ranOk) {
      return SkillAcquireResult(
        success: false,
        message: last?.stderr.trim().isNotEmpty == true
            ? last!.stderr.trim()
            : (last?.stdout.trim().isNotEmpty == true
                  ? last!.stdout.trim()
                  : 'Installation failed.'),
      );
    }

    final after = await _listSkillDirsWithSkillMd();
    final newDirs = after.difference(before).toList()..sort();

    final String? chosen;
    if (newDirs.isEmpty) {
      // Script may have refreshed an existing matched dir (re-register path).
      chosen = _pickExistingMatchedDirectory(
        existingDirs: after,
        primaryDirectory: acquire.primaryDirectory,
        packageUrl: acquire.package,
      );
      if (chosen == null) {
        return const SkillAcquireResult(
          success: false,
          message:
              'Install command succeeded but no SKILL.md was found under '
              'skills/installed/.',
        );
      }
    } else {
      chosen = _pickPrimaryDirectory(
        newDirs: newDirs,
        primaryDirectory: acquire.primaryDirectory,
        packageUrl: acquire.package,
      );
      if (chosen == null) {
        return SkillAcquireResult(
          success: false,
          message:
              'Multiple new skill directories appeared '
              '(${newDirs.join(', ')}); set primaryDirectory or ensure one '
              'matches the script URL basename.',
        );
      }
    }

    try {
      final skill = await _registerDirectory(
        id: expectedLocalId,
        directory: chosen,
      );
      return SkillAcquireResult(
        success: true,
        skillId: skill.id,
        message: displayName.isEmpty ? 'Installed.' : 'Installed $displayName.',
      );
    } catch (e) {
      return SkillAcquireResult(success: false, message: e.toString());
    }
  }

  /// Primary command for [acquire], then one per `alternatives` entry
  /// (`"<kind>:<arg>"`).
  List<CliInstallerCommand> _installCommands(SkillAcquireSpec acquire) {
    final commands = <CliInstallerCommand>[];
    final primary = _commandForKind(acquire.kind, acquire.package);
    if (primary != null) commands.add(primary);
    for (final alt in acquire.alternatives) {
      final idx = alt.indexOf(':');
      if (idx <= 0) continue;
      final kind = alt.substring(0, idx);
      final arg = alt.substring(idx + 1);
      final cmd = _commandForKind(kind, arg);
      if (cmd != null) commands.add(cmd);
    }
    return commands;
  }

  CliInstallerCommand? _commandForKind(String kind, String? arg) {
    final target = arg?.trim() ?? '';
    if (target.isEmpty) return null;
    switch (kind) {
      case 'script':
        if (!_isSafeScriptUrl(target)) return null;
        return CliInstallerCommand('sh', ['-c', 'curl -fsSL "$target" | sh']);
      default:
        return null;
    }
  }

  /// Same checks as [ExtensionAcquisitionEngine] (duplicated for v1).
  static bool _isSafeScriptUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) return false;
    return !RegExp(r'''[\s"'`$\\;|&<>()]''').hasMatch(url);
  }

  static String? _pickPrimaryDirectory({
    required List<String> newDirs,
    required String? primaryDirectory,
    required String? packageUrl,
  }) {
    final preferred = primaryDirectory?.trim();
    if (preferred != null && preferred.isNotEmpty) {
      if (newDirs.contains(preferred)) return preferred;
    }

    final urlBase = _urlPathBasename(packageUrl);
    if (urlBase != null) {
      final matches = newDirs.where((d) => d == urlBase).toList();
      if (matches.length == 1) return matches.single;
    }

    if (newDirs.length == 1) return newDirs.single;
    return null;
  }

  /// When the script creates no *new* dirs, allow re-registering an existing
  /// dir that matches [primaryDirectory] or the script URL basename.
  static String? _pickExistingMatchedDirectory({
    required Set<String> existingDirs,
    required String? primaryDirectory,
    required String? packageUrl,
  }) {
    final preferred = primaryDirectory?.trim();
    if (preferred != null &&
        preferred.isNotEmpty &&
        existingDirs.contains(preferred)) {
      return preferred;
    }
    final urlBase = _urlPathBasename(packageUrl);
    if (urlBase != null && existingDirs.contains(urlBase)) {
      return urlBase;
    }
    return null;
  }

  static String? _urlPathBasename(String? packageUrl) {
    if (packageUrl == null || packageUrl.trim().isEmpty) return null;
    final uri = Uri.tryParse(packageUrl.trim());
    if (uri == null) return null;
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segments.isEmpty) return null;
    return segments.last;
  }
}
