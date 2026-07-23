import 'dart:io';

import 'package:path/path.dart' as p;

import '../../models/discoverable_team.dart';
import '../../models/skill.dart';
import '../../models/skill_acquire_spec.dart';
import '../cli/installer_types.dart';
import '../storage/app_storage.dart';
import 'skill_install_service.dart';
import 'skill_manifest_service.dart';

typedef SkillInstallRunner =
    Future<CliInstallerCommandResult> Function(CliInstallerCommand command);

typedef SkillGitDirInstaller =
    Future<Skill> Function(DiscoverableSkill discovery, {bool overwrite});

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
class SkillAcquisitionEngine {
  SkillAcquisitionEngine({
    SkillInstallRunner? runner,
    required SkillGitDirInstaller installGitDir,
    bool Function()? isLocalAcquireSupported,
    SkillDirectoryRegistrar? registerDirectory,
    Future<Set<String>> Function()? listSkillDirsWithSkillMd,
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
           listSkillDirsWithSkillMd ?? _defaultListSkillDirsWithSkillMd;

  final SkillInstallRunner _runner;
  final SkillGitDirInstaller _installGitDir;
  final bool Function() _isLocalAcquireSupported;
  final SkillDirectoryRegistrar _registerDirectory;
  final Future<Set<String>> Function() _listSkillDirsWithSkillMd;

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

  Future<SkillAcquireResult> install(SkillDependencyRef ref) {
    return _install(
      acquire: ref.resolvedAcquire,
      discovery: ref.toDiscoverableSkill(),
      expectedLocalId: ref.expectedLocalId,
      displayName: ref.name,
    );
  }

  Future<SkillAcquireResult> installDiscoverable(DiscoverableSkill d) {
    final acquire = d.acquire ?? const SkillAcquireSpec(kind: 'git-dir');
    return _install(
      acquire: acquire,
      discovery: d,
      expectedLocalId: _expectedIdForDiscoverable(d, acquire),
      displayName: d.name,
    );
  }

  Future<SkillAcquireResult> _install({
    required SkillAcquireSpec acquire,
    required DiscoverableSkill discovery,
    required String expectedLocalId,
    required String displayName,
  }) async {
    switch (acquire.kind) {
      case 'git-dir':
        try {
          final skill = await _installGitDir(discovery);
          return SkillAcquireResult(success: true, skillId: skill.id);
        } catch (e) {
          return SkillAcquireResult(success: false, message: e.toString());
        }
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
    if (newDirs.isEmpty) {
      return const SkillAcquireResult(
        success: false,
        message:
            'Install command succeeded but no SKILL.md was found under '
            'skills/installed/.',
      );
    }

    final chosen = _pickPrimaryDirectory(
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

  static String? _urlPathBasename(String? packageUrl) {
    if (packageUrl == null || packageUrl.trim().isEmpty) return null;
    final uri = Uri.tryParse(packageUrl.trim());
    if (uri == null) return null;
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segments.isEmpty) return null;
    return segments.last;
  }

  static String _expectedIdForDiscoverable(
    DiscoverableSkill d,
    SkillAcquireSpec acquire,
  ) {
    final explicit = d.id?.trim();
    if (explicit != null && explicit.isNotEmpty) return explicit;
    final key = d.key.trim();
    if (key.isNotEmpty) return key;
    if (acquire.kind == 'script') {
      return _scriptIdFromPackageUrl(acquire.package);
    }
    final basename = p.basename(d.directory);
    if (d.repoOwner.isNotEmpty && d.repoName.isNotEmpty && basename.isNotEmpty) {
      return '${d.repoOwner}/${d.repoName}:$basename';
    }
    return basename.isEmpty ? 'local:unknown' : 'local:$basename';
  }

  static String _scriptIdFromPackageUrl(String? package) {
    if (package == null || package.trim().isEmpty) {
      return 'script:unknown';
    }
    final uri = Uri.tryParse(package.trim());
    if (uri == null || uri.host.isEmpty) {
      return 'script:unknown';
    }
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    final basename = segments.isEmpty ? 'unknown' : segments.last;
    return 'script:${uri.host}/$basename';
  }
}
