import 'dart:io';

import 'package:path/path.dart' as p;

import '../../models/discoverable_team.dart';
import '../../models/skill.dart';
import '../../models/skill_pack.dart';
import '../../models/skill_pack_instruction.dart';
import '../../utils/logging/logger.dart';
import '../cli/installer_types.dart';
import '../io/filesystem.dart';
import '../storage/app_storage.dart';
import 'acquire/skill_acquire_context.dart';
import 'skill_install_service.dart';
import 'skill_manifest_service.dart';
import 'skill_pack_install_store.dart';
import 'skill_pack_registry.dart';
import 'skill_repo_disk_cache_service.dart';

typedef SkillInstallRunner =
    Future<CliInstallerCommandResult> Function(CliInstallerCommand command);

typedef SkillGitDirInstaller =
    Future<Skill> Function(
      DiscoverableSkill discovery, {
      bool overwrite,
      String? idOverride,
    });

typedef SkillDirectoryRegistrar =
    Future<Skill> Function({required String id, required String directory});

typedef SkillRepoEnsureSynced =
    Future<SkillRepoSyncResult> Function(SkillRepo repo);

class SkillAcquireResult {
  const SkillAcquireResult({
    required this.success,
    this.message = '',
    this.skillId,
    this.pathExports = const [],
    this.envExports = const {},
    this.installedSkillIds = const [],
    this.syncRoot,
  });

  final bool success;
  final String message;
  final String? skillId;
  final List<String> pathExports;
  final Map<String, String> envExports;
  final List<String> installedSkillIds;
  final String? syncRoot;
}

class _InstrResult {
  const _InstrResult({required this.success, this.message = ''});

  final bool success;
  final String message;

  static const ok = _InstrResult(success: true);
}

/// Runs Dockerfile-like [SkillPackInstruction] lists via type dispatch.
class SkillAcquisitionEngine {
  SkillAcquisitionEngine({
    SkillInstallRunner? runner,
    required SkillGitDirInstaller installGitDir,
    bool Function()? isLocalAcquireSupported,
    SkillDirectoryRegistrar? registerDirectory,
    Future<Set<String>> Function()? listSkillDirsWithSkillMd,
    SkillPackRegistry? packRegistry,
    SkillRepoDiskCacheService? repoCache,
    SkillRepoEnsureSynced? ensureSynced,
    SkillPackInstallStore? packInstallStore,
    Filesystem? fs,
  }) : _runner = runner ?? _defaultLocalRunner,
       _usesDefaultRunner = runner == null,
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
       _packRegistry = packRegistry ?? SkillPackRegistry(),
       _repoCache = repoCache ?? SkillRepoDiskCacheService(),
       _ensureSynced = ensureSynced,
       _packInstallStore = packInstallStore ?? SkillPackInstallStore(),
       _fs = fs;

  final SkillInstallRunner _runner;
  final bool _usesDefaultRunner;
  final SkillGitDirInstaller _installGitDir;
  final bool Function() _isLocalAcquireSupported;
  final SkillDirectoryRegistrar _registerDirectory;
  final Future<Set<String>> Function() _listSkillDirsWithSkillMd;
  final SkillPackRegistry _packRegistry;
  final SkillRepoDiskCacheService _repoCache;
  final SkillRepoEnsureSynced? _ensureSynced;
  final SkillPackInstallStore _packInstallStore;
  final Filesystem? _fs;

  Filesystem get fs => _fs ?? AppStorage.fs;

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
  }) async {
    final packId = ref.packId?.trim();
    if (packId != null && packId.isNotEmpty) {
      return _runPack(
        packId: packId,
        expectedSkillId: ref.expectedLocalId,
        overwrite: overwrite,
      );
    }
    final install = ref.resolvedInstall;
    if (install == null || install.isEmpty) {
      return const SkillAcquireResult(
        success: false,
        message: 'Skill dependency has no install instructions.',
      );
    }
    return _runInstall(
      install: install,
      expectedSkillId: ref.expectedLocalId,
      overwrite: overwrite,
    );
  }

  Future<SkillAcquireResult> installDiscoverable(
    DiscoverableSkill d, {
    bool overwrite = false,
  }) async {
    final packId = d.packId?.trim();
    if (packId != null && packId.isNotEmpty) {
      return _runPack(
        packId: packId,
        expectedSkillId: d.expectedLocalId,
        overwrite: overwrite,
      );
    }
    final install = d.resolvedInstall;
    if (install == null || install.isEmpty) {
      return const SkillAcquireResult(
        success: false,
        message: 'Discoverable skill has no install instructions.',
      );
    }
    return _runInstall(
      install: install,
      expectedSkillId: d.expectedLocalId,
      overwrite: overwrite,
    );
  }

  /// Direct git-dir install (clone repo + register SKILL.md dir) without
  /// instruction dispatch. Exposed for direct marketplace installs.
  Future<Skill> installGitDir(
    DiscoverableSkill discovery, {
    bool overwrite = false,
    String? idOverride,
  }) => _installGitDir(discovery, overwrite: overwrite, idOverride: idOverride);

  Future<SkillAcquireResult> _runPack({
    required String packId,
    required String expectedSkillId,
    required bool overwrite,
  }) async {
    var pack = _packRegistry.byId(packId);
    if (pack == null) {
      await _packRegistry.ensureLoaded();
      pack = _packRegistry.byId(packId);
    }
    if (pack == null) {
      return SkillAcquireResult(
        success: false,
        message: 'Unknown skill pack: $packId',
      );
    }
    if (pack.install.isEmpty) {
      return SkillAcquireResult(
        success: false,
        message: 'Skill pack $packId has empty install.',
      );
    }
    final result = await _runInstall(
      install: pack.install,
      expectedSkillId: expectedSkillId,
      overwrite: overwrite,
      pack: pack,
    );
    if (!result.success) return result;
    if (expectedSkillId.isNotEmpty &&
        !result.installedSkillIds.contains(expectedSkillId)) {
      return SkillAcquireResult(
        success: false,
        message: 'Skill $expectedSkillId was not registered by pack $packId.',
      );
    }
    await _packInstallStore.save(
      SkillPackInstallRecord(
        packId: pack.id,
        skillIds: List.unmodifiable(result.installedSkillIds),
        pathExports: result.pathExports,
        envExports: result.envExports,
        installedAt: DateTime.now().millisecondsSinceEpoch,
        syncRoot: result.syncRoot,
      ),
    );
    return result;
  }

  Future<SkillAcquireResult> _runInstall({
    required List<SkillPackInstruction> install,
    required String expectedSkillId,
    required bool overwrite,
    SkillPack? pack,
  }) async {
    if (install.isEmpty) {
      return const SkillAcquireResult(
        success: false,
        message: 'Install has no instructions.',
      );
    }

    final ctx = SkillAcquireContext(
      overwrite: overwrite,
      expectedSkillId: expectedSkillId,
      pack: pack,
    );

    for (var i = 0; i < install.length; i++) {
      final step = install[i];
      final stepResult = await _dispatch(step, ctx, index: i);
      if (!stepResult.success) {
        final optional =
            (step is RunInstruction && step.optional) ||
            (step is ScriptInstruction && step.optional);
        if (optional) {
          appLogger.w(
            '[skills] optional install[$i] failed: ${stepResult.message}',
          );
          continue;
        }
        return SkillAcquireResult(
          success: false,
          message: stepResult.message.isEmpty
              ? 'install[$i] failed'
              : stepResult.message,
        );
      }
    }

    return SkillAcquireResult(
      success: true,
      skillId: expectedSkillId,
      pathExports: List.unmodifiable(ctx.pathExports),
      envExports: Map.unmodifiable(ctx.envExports),
      installedSkillIds: List.unmodifiable(ctx.installedSkillIds),
      syncRoot: ctx.syncRoot,
    );
  }

  Future<_InstrResult> _dispatch(
    SkillPackInstruction step,
    SkillAcquireContext ctx, {
    required int index,
  }) {
    return switch (step) {
      FromInstruction() => _onFrom(step, ctx, index: index),
      ScriptInstruction() => _onScript(step, ctx, index: index),
      CopyInstruction() => _onCopy(step, ctx, index: index),
      SkillsInstruction() => _onSkills(step, ctx, index: index),
      ShellInstruction() => _onShell(step, ctx),
      RunInstruction() => _onRun(step, ctx, index: index),
      WorkdirInstruction() => _onWorkdir(step, ctx, index: index),
      PathInstruction() => _onPath(step, ctx, index: index),
      EnvInstruction() => _onEnv(step, ctx, index: index),
    };
  }

  Future<_InstrResult> _onFrom(
    FromInstruction step,
    SkillAcquireContext ctx, {
    required int index,
  }) async {
    final repo = SkillRepo(
      owner: step.owner,
      name: step.name,
      branch: step.branch,
    );
    try {
      final sync = _ensureSynced ?? _repoCache.ensureSynced;
      await sync(repo);
    } catch (e) {
      return _InstrResult(success: false, message: 'install[$index] FROM: $e');
    }
    final syncRoot = fs.pathContext.join(
      AppStorage.paths.skillRepoCacheDir,
      SkillRepoDiskCacheService.repoKey(repo),
      'files',
    );
    ctx.syncRoot = syncRoot;
    ctx.syncOwner = step.owner;
    ctx.syncName = step.name;
    ctx.syncBranch = step.branch;
    ctx.workdir = '';
    return _InstrResult.ok;
  }

  Future<_InstrResult> _onScript(
    ScriptInstruction step,
    SkillAcquireContext ctx, {
    required int index,
  }) async {
    if (!_isLocalAcquireSupported()) {
      return _InstrResult(
        success: false,
        message: 'install[$index] SCRIPT: not supported on this host',
      );
    }
    final urls = <String>[step.url, ...step.alternatives];
    if (!_isSafeScriptUrl(step.url)) {
      return _InstrResult(
        success: false,
        message: 'install[$index] SCRIPT: unsafe script URL',
      );
    }
    final before = await _listSkillDirsWithSkillMd();
    CliInstallerCommandResult? last;
    var ok = false;
    for (final url in urls) {
      if (!_isSafeScriptUrl(url)) continue;
      last = await _runner(
        CliInstallerCommand('sh', ['-c', 'curl -fsSL "$url" | sh']),
      );
      if (last.exitCode == 0) {
        ok = true;
        break;
      }
    }
    if (!ok) {
      return _InstrResult(
        success: false,
        message: last?.stderr.trim().isNotEmpty == true
            ? last!.stderr.trim()
            : 'install[$index] SCRIPT: installation failed',
      );
    }

    final after = await _listSkillDirsWithSkillMd();
    final newDirs = after.difference(before).toList()..sort();
    final primary = step.primaryDirectory?.trim();
    final id = (step.id?.trim().isNotEmpty == true)
        ? step.id!.trim()
        : ctx.expectedSkillId;
    final String chosen;
    if (newDirs.isEmpty) {
      if (primary != null && after.contains(primary)) {
        chosen = primary;
      } else {
        return _InstrResult(
          success: false,
          message:
              'install[$index] SCRIPT: succeeded but no SKILL.md under '
              'skills/installed/',
        );
      }
    } else if (newDirs.length == 1) {
      chosen = newDirs.single;
    } else if (primary != null && newDirs.contains(primary)) {
      chosen = primary;
    } else {
      return _InstrResult(
        success: false,
        message:
            'install[$index] SCRIPT: multiple new skill dirs '
            '(${newDirs.join(', ')}); set primaryDirectory',
      );
    }
    try {
      await _registerDirectory(id: id, directory: chosen);
      if (!ctx.installedSkillIds.contains(id)) {
        ctx.installedSkillIds.add(id);
      }
      // SCRIPT establishes a workspace root at the registered skill dir parent.
      if (!ctx.hasWorkspace) {
        final skillsDir = AppPaths.skillsDirForTeampilotRoot(
          AppStorage.paths.basePath,
        );
        ctx.syncRoot = fs.pathContext.join(skillsDir, chosen);
        ctx.workdir = '';
      }
      return _InstrResult.ok;
    } catch (e) {
      return _InstrResult(success: false, message: e.toString());
    }
  }

  Future<_InstrResult> _onCopy(
    CopyInstruction step,
    SkillAcquireContext ctx, {
    required int index,
  }) async {
    if (!ctx.hasWorkspace) {
      return _InstrResult(
        success: false,
        message: 'install[$index] COPY: requires prior FROM or SCRIPT',
      );
    }
    final String fromPath;
    final String toPath;
    try {
      fromPath = ctx.resolveRelative(step.from);
      toPath = ctx.resolveWorkdirRelative(step.to);
    } on StateError catch (e) {
      return _InstrResult(
        success: false,
        message: 'install[$index] COPY: ${e.message}',
      );
    }
    final fromStat = await fs.stat(fromPath);
    if (!fromStat.exists) {
      return _InstrResult(
        success: false,
        message: 'install[$index] COPY: source missing: $fromPath',
      );
    }
    await fs.ensureDir(fs.pathContext.dirname(toPath));
    if (fromStat.isDirectory) {
      await fs.copyTree(source: fromPath, destination: toPath);
    } else {
      await fs.copyFile(fromPath, toPath);
    }
    return _InstrResult.ok;
  }

  Future<_InstrResult> _onSkills(
    SkillsInstruction step,
    SkillAcquireContext ctx, {
    required int index,
  }) async {
    if (!ctx.hasWorkspace) {
      return _InstrResult(
        success: false,
        message: 'install[$index] SKILLS: requires prior FROM or SCRIPT',
      );
    }
    final dirs = await _resolveSkillDirs(step, ctx.syncRoot!);
    final pack = ctx.pack;
    // Spec: only use expectedSkillId when pack==null and exactly one dir.
    final useExpectedId =
        pack == null && ctx.expectedSkillId.isNotEmpty && dirs.length == 1;

    for (final dir in dirs) {
      final basename = p.basename(dir);
      final id = useExpectedId
          ? ctx.expectedSkillId
          : pack != null
          ? '${pack.id}:$basename'
          : basename;
      final discovery = DiscoverableSkill(
        key: id,
        name: basename,
        description: '',
        directory: dir,
        repoOwner: ctx.syncOwner ?? '',
        repoName: ctx.syncName ?? '',
        repoBranch: ctx.syncBranch ?? 'main',
        id: id,
        packId: pack?.id,
      );
      try {
        await _installGitDir(
          discovery,
          overwrite: ctx.overwrite,
          idOverride: id,
        );
        if (!ctx.installedSkillIds.contains(id)) {
          ctx.installedSkillIds.add(id);
        }
      } catch (e) {
        if (!ctx.overwrite &&
            e.toString().toLowerCase().contains('already exists')) {
          if (!ctx.installedSkillIds.contains(id)) {
            ctx.installedSkillIds.add(id);
          }
          continue;
        }
        return _InstrResult(
          success: false,
          message: 'install[$index] SKILLS: $e',
        );
      }
    }
    return _InstrResult.ok;
  }

  Future<_InstrResult> _onShell(
    ShellInstruction step,
    SkillAcquireContext ctx,
  ) async {
    ctx.shell = List<String>.from(step.wrapper);
    return _InstrResult.ok;
  }

  Future<_InstrResult> _onRun(
    RunInstruction step,
    SkillAcquireContext ctx, {
    required int index,
  }) async {
    if (!ctx.hasWorkspace) {
      return _InstrResult(
        success: false,
        message: 'install[$index] RUN: requires prior FROM or SCRIPT',
      );
    }
    if (!_isLocalAcquireSupported()) {
      return _InstrResult(
        success: false,
        message: 'install[$index] RUN: not supported on this host',
      );
    }
    final cwd = ctx.effectiveWorkdir;
    final CliInstallerCommand command;
    if (step.exec != null) {
      final exec = step.exec!;
      command = CliInstallerCommand(exec.first, exec.skip(1).toList());
    } else {
      final shell = ctx.shell;
      if (shell.isEmpty) {
        return _InstrResult(
          success: false,
          message: 'install[$index] RUN: empty SHELL',
        );
      }
      command = CliInstallerCommand(shell.first, [
        ...shell.skip(1),
        step.shell!,
      ]);
    }
    try {
      final CliInstallerCommandResult result;
      if (_usesDefaultRunner) {
        final ran = await Process.run(
          command.executable,
          command.arguments,
          workingDirectory: cwd,
        );
        result = CliInstallerCommandResult(
          exitCode: ran.exitCode,
          stdout: ran.stdout?.toString() ?? '',
          stderr: ran.stderr?.toString() ?? '',
        );
      } else {
        result = await _runner(command);
      }
      if (result.exitCode != 0) {
        return _InstrResult(
          success: false,
          message: result.stderr.trim().isNotEmpty
              ? result.stderr.trim()
              : result.stdout.trim().isNotEmpty
              ? result.stdout.trim()
              : 'install[$index] RUN: failed',
        );
      }
      return _InstrResult.ok;
    } catch (e) {
      return _InstrResult(success: false, message: e.toString());
    }
  }

  Future<_InstrResult> _onWorkdir(
    WorkdirInstruction step,
    SkillAcquireContext ctx, {
    required int index,
  }) async {
    if (!ctx.hasWorkspace) {
      return _InstrResult(
        success: false,
        message: 'install[$index] WORKDIR: requires prior FROM or SCRIPT',
      );
    }
    try {
      // Validate path stays under sync root.
      ctx.resolveRelative(step.path);
      ctx.workdir = step.path;
      return _InstrResult.ok;
    } on StateError catch (e) {
      return _InstrResult(
        success: false,
        message: 'install[$index] WORKDIR: ${e.message}',
      );
    }
  }

  Future<_InstrResult> _onPath(
    PathInstruction step,
    SkillAcquireContext ctx, {
    required int index,
  }) async {
    if (!ctx.hasWorkspace) {
      return _InstrResult(
        success: false,
        message: 'install[$index] PATH: requires prior FROM or SCRIPT',
      );
    }
    try {
      final abs = [
        for (final entry in step.entries) ctx.resolveRelative(entry),
      ];
      ctx.appendPathExports(abs);
      return _InstrResult.ok;
    } on StateError catch (e) {
      return _InstrResult(
        success: false,
        message: 'install[$index] PATH: ${e.message}',
      );
    }
  }

  Future<_InstrResult> _onEnv(
    EnvInstruction step,
    SkillAcquireContext ctx, {
    required int index,
  }) async {
    final resolved = <String, String>{};
    for (final e in step.entries.entries) {
      var value = e.value;
      if (ctx.hasWorkspace &&
          value.isNotEmpty &&
          !_isAbsolutePath(value) &&
          !value.contains(r'$') &&
          (value.contains('/') || value.contains(r'\'))) {
        try {
          value = ctx.resolveRelative(value);
        } on StateError {
          // Keep literal when not a resolvable relative path.
        }
      }
      resolved[e.key] = value;
    }
    ctx.mergeEnv(resolved);
    return _InstrResult.ok;
  }

  Future<List<String>> _resolveSkillDirs(
    SkillsInstruction step,
    String syncRoot,
  ) async {
    final discovered = await _discoverDirectSkillDirs(syncRoot);
    final selected = <String>{};
    if (step.includeAll) {
      selected.addAll(discovered);
    } else {
      for (final name in step.include) {
        if (discovered.contains(name)) {
          selected.add(name);
          continue;
        }
        final skillMd = fs.pathContext.join(syncRoot, name, 'SKILL.md');
        if ((await fs.stat(skillMd)).isFile) {
          selected.add(name);
        }
      }
    }
    for (final ex in step.exclude) {
      selected.remove(ex);
    }
    final out = selected.toList()..sort();
    return out;
  }

  Future<List<String>> _discoverDirectSkillDirs(String syncRoot) async {
    if (!(await fs.stat(syncRoot)).isDirectory) return const [];
    final out = <String>[];
    for (final entry in await fs.listDir(syncRoot)) {
      if (!entry.isDirectory) continue;
      final skillMd = fs.pathContext.join(syncRoot, entry.name, 'SKILL.md');
      if ((await fs.stat(skillMd)).isFile) {
        out.add(entry.name);
      }
    }
    return out;
  }

  static bool _isSafeScriptUrl(String url) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) return false;
    const banned = r'''\s'"\$\\;`|&<>()''';
    return !RegExp('[$banned]').hasMatch(url);
  }

  static bool _isAbsolutePath(String path) {
    if (path.startsWith('/') || path.startsWith(r'\')) return true;
    return path.length >= 2 && path[1] == ':';
  }
}
