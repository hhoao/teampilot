import 'dart:io';

import '../../models/discoverable_team.dart';
import '../../models/skill.dart';
import '../../models/skill_install_recipe.dart';
import '../../models/skill_pack.dart';
import '../cli/installer_types.dart';
import '../io/filesystem.dart';
import '../storage/app_storage.dart';
import 'acquire/skill_acquire_context.dart';
import 'acquire/skill_step_handler.dart';
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
    Future<Skill> Function({
      required String id,
      required String directory,
    });

class SkillAcquireResult {
  const SkillAcquireResult({
    required this.success,
    this.message = '',
    this.skillId,
    this.pathExports = const [],
  });

  final bool success;
  final String message;
  final String? skillId;
  final List<String> pathExports;
}

/// Runs [SkillInstallRecipe] graphs via a handler registry.
class SkillAcquisitionEngine {
  SkillAcquisitionEngine({
    SkillInstallRunner? runner,
    required SkillGitDirInstaller installGitDir,
    bool Function()? isLocalAcquireSupported,
    SkillDirectoryRegistrar? registerDirectory,
    Future<Set<String>> Function()? listSkillDirsWithSkillMd,
    SkillPackRegistry? packRegistry,
    SkillRepoDiskCacheService? repoCache,
    SkillPackInstallStore? packInstallStore,
    Filesystem? fs,
    Map<String, SkillStepHandler>? handlers,
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
       _packRegistry = packRegistry ?? SkillPackRegistry(),
       _repoCache = repoCache ?? SkillRepoDiskCacheService(),
       _packInstallStore = packInstallStore ?? SkillPackInstallStore(),
       _fs = fs {
    _handlers = {
      'git.sync': _handleGitSync,
      'skill.install-dir': _handleSkillInstallDir,
      'skill.register-pack': _handleSkillRegisterPack,
      'fs.materialize': _handleFsMaterialize,
      'script.run': _handleScriptRun,
      ...?handlers,
    };
  }

  final SkillInstallRunner _runner;
  final SkillGitDirInstaller _installGitDir;
  final bool Function() _isLocalAcquireSupported;
  final SkillDirectoryRegistrar _registerDirectory;
  final Future<Set<String>> Function() _listSkillDirsWithSkillMd;
  final SkillPackRegistry _packRegistry;
  final SkillRepoDiskCacheService _repoCache;
  final SkillPackInstallStore _packInstallStore;
  final Filesystem? _fs;
  late final Map<String, SkillStepHandler> _handlers;

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
    final recipe = ref.resolvedRecipe;
    if (recipe == null || recipe.isEmpty) {
      return const SkillAcquireResult(
        success: false,
        message: 'Skill dependency has no install recipe.',
      );
    }
    return _runRecipe(
      recipe: recipe,
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
    final recipe = d.resolvedRecipe;
    if (recipe == null || recipe.isEmpty) {
      return const SkillAcquireResult(
        success: false,
        message: 'Discoverable skill has no install recipe.',
      );
    }
    return _runRecipe(
      recipe: recipe,
      expectedSkillId: d.expectedLocalId,
      overwrite: overwrite,
      discovery: d,
    );
  }

  Future<SkillAcquireResult> _runPack({
    required String packId,
    required String expectedSkillId,
    required bool overwrite,
  }) async {
    final pack = _packRegistry.byId(packId);
    if (pack == null) {
      return SkillAcquireResult(
        success: false,
        message: 'Unknown skill pack: $packId',
      );
    }
    if (pack.entryById(expectedSkillId) == null &&
        !pack.skills.any((s) => s.id == expectedSkillId)) {
      // Allow expected id even if only listed in exports; still require catalog
      // membership when skills[] is non-empty.
      if (pack.skills.isNotEmpty) {
        return SkillAcquireResult(
          success: false,
          message: 'Skill $expectedSkillId is not in pack $packId.',
        );
      }
    }
    final packRoot = _packInstallStore.packRootFor(pack.id);
    final packBin = _packInstallStore.packBinFor(pack.id);
    await fs.ensureDir(packRoot);
    final result = await _runRecipe(
      recipe: pack.recipe,
      expectedSkillId: expectedSkillId,
      overwrite: overwrite,
      pack: pack,
      packRoot: packRoot,
      packBin: packBin,
    );
    if (result.success) {
      await _packInstallStore.save(
        SkillPackInstallRecord(
          packId: pack.id,
          skillIds: [for (final s in pack.skills) s.id],
          pathExports: result.pathExports,
          envExports: const {},
          installedAt: DateTime.now().millisecondsSinceEpoch,
          packBin: packBin,
        ),
      );
    }
    return result;
  }

  Future<SkillAcquireResult> _runRecipe({
    required SkillInstallRecipe recipe,
    required String expectedSkillId,
    required bool overwrite,
    SkillPack? pack,
    DiscoverableSkill? discovery,
    String? packRoot,
    String? packBin,
  }) async {
    final List<SkillInstallStep> ordered;
    try {
      ordered = recipe.sortedSteps();
    } catch (e) {
      return SkillAcquireResult(success: false, message: e.toString());
    }
    if (ordered.isEmpty) {
      return const SkillAcquireResult(
        success: false,
        message: 'Install recipe has no steps.',
      );
    }

    final ctx = SkillAcquireContext(
      overwrite: overwrite,
      expectedSkillId: expectedSkillId,
      pack: pack,
    );
    if (packRoot != null) ctx.packRoot = packRoot;
    if (packBin != null) ctx.packBin = packBin;
    if (discovery != null) {
      ctx.vars['DISCOVERY_DIR'] = discovery.directory;
      ctx.vars['DISCOVERY_ID'] = discovery.expectedLocalId;
      ctx.vars['DISCOVERY_NAME'] = discovery.name;
      ctx.vars['REPO_OWNER'] = discovery.repoOwner;
      ctx.vars['REPO_NAME'] = discovery.repoName;
      ctx.vars['REPO_BRANCH'] = discovery.repoBranch;
    }

    for (final step in ordered) {
      final handler = _handlers[step.uses];
      if (handler == null) {
        final msg = 'Unknown skill install step: ${step.uses}';
        if (step.optional) continue;
        return SkillAcquireResult(success: false, message: msg);
      }
      final stepResult = await handler(step, ctx);
      if (!stepResult.success) {
        if (step.optional) continue;
        return SkillAcquireResult(
          success: false,
          message: stepResult.message.isEmpty
              ? 'Step ${step.id} failed'
              : stepResult.message,
        );
      }
    }

    ctx.applyExports(recipe.exports);
    if (ctx.installedSkillIds.isEmpty && expectedSkillId.isNotEmpty) {
      ctx.installedSkillIds.add(expectedSkillId);
    }
    return SkillAcquireResult(
      success: true,
      skillId: expectedSkillId,
      pathExports: List.unmodifiable(ctx.pathExports),
    );
  }

  Future<SkillStepResult> _handleGitSync(
    SkillInstallStep step,
    SkillAcquireContext ctx,
  ) async {
    final owner =
        (step.withArgs['owner'] as String?)?.trim() ??
        ctx.pack?.repoOwner ??
        ctx.vars['REPO_OWNER'] ??
        '';
    final name =
        (step.withArgs['name'] as String?)?.trim() ??
        ctx.pack?.repoName ??
        ctx.vars['REPO_NAME'] ??
        '';
    final branch =
        (step.withArgs['branch'] as String?)?.trim() ??
        ctx.pack?.repoBranch ??
        ctx.vars['REPO_BRANCH'] ??
        'main';
    if (owner.isEmpty || name.isEmpty) {
      return const SkillStepResult(
        success: false,
        message: 'git.sync requires owner and name',
      );
    }
    final repo = SkillRepo(owner: owner, name: name, branch: branch);
    try {
      await _repoCache.ensureSynced(repo);
    } catch (e) {
      return SkillStepResult(success: false, message: e.toString());
    }
    final syncRoot = fs.pathContext.join(
      AppStorage.paths.skillRepoCacheDir,
      SkillRepoDiskCacheService.repoKey(repo),
      'files',
    );
    ctx.syncRoot = syncRoot;
    return SkillStepResult.ok;
  }

  Future<SkillStepResult> _handleSkillInstallDir(
    SkillInstallStep step,
    SkillAcquireContext ctx,
  ) async {
    final directory =
        (step.withArgs['directory'] as String?)?.trim() ??
        ctx.vars['DISCOVERY_DIR'] ??
        '';
    final id =
        (step.withArgs['id'] as String?)?.trim() ??
        ctx.expectedSkillId;
    final skillName =
        (step.withArgs['name'] as String?)?.trim() ??
        directory.split('/').last;
    final owner =
        ctx.pack?.repoOwner ??
        ctx.vars['REPO_OWNER'] ??
        (step.withArgs['owner'] as String?)?.trim() ??
        '';
    final repoName =
        ctx.pack?.repoName ??
        ctx.vars['REPO_NAME'] ??
        (step.withArgs['repo'] as String?)?.trim() ??
        '';
    final branch =
        ctx.pack?.repoBranch ??
        ctx.vars['REPO_BRANCH'] ??
        (step.withArgs['branch'] as String?)?.trim() ??
        'main';
    if (directory.isEmpty || id.isEmpty) {
      return const SkillStepResult(
        success: false,
        message: 'skill.install-dir requires directory and id',
      );
    }
    final discovery = DiscoverableSkill(
      key: id,
      name: skillName,
      description: '',
      directory: directory,
      repoOwner: owner,
      repoName: repoName,
      repoBranch: branch,
      id: id,
      packId: ctx.pack?.id,
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
      return SkillStepResult.ok;
    } catch (e) {
      if (!ctx.overwrite && e.toString().toLowerCase().contains('already exists')) {
        if (!ctx.installedSkillIds.contains(id)) {
          ctx.installedSkillIds.add(id);
        }
        return SkillStepResult.ok;
      }
      return SkillStepResult(success: false, message: e.toString());
    }
  }

  Future<SkillStepResult> _handleSkillRegisterPack(
    SkillInstallStep step,
    SkillAcquireContext ctx,
  ) async {
    final pack = ctx.pack;
    if (pack == null || pack.skills.isEmpty) {
      return const SkillStepResult(
        success: false,
        message: 'skill.register-pack requires an active pack with skills',
      );
    }
    for (final entry in pack.skills) {
      final stepResult = await _handleSkillInstallDir(
        SkillInstallStep(
          id: 'install-${entry.id}',
          uses: 'skill.install-dir',
          withArgs: {
            'directory': entry.directory,
            'id': entry.id,
            'name': entry.name,
          },
        ),
        ctx,
      );
      if (!stepResult.success) return stepResult;
    }
    return SkillStepResult.ok;
  }

  Future<SkillStepResult> _handleFsMaterialize(
    SkillInstallStep step,
    SkillAcquireContext ctx,
  ) async {
    final fromRel = (step.withArgs['from'] as String?)?.trim() ?? '';
    final toTemplate =
        (step.withArgs['to'] as String?)?.trim() ?? '\$PACK_BIN';
    final mode = (step.withArgs['mode'] as String?)?.trim() ?? 'link';
    final syncRoot = ctx.syncRoot;
    if (fromRel.isEmpty || syncRoot == null || syncRoot.isEmpty) {
      return const SkillStepResult(
        success: false,
        message: 'fs.materialize requires sync root and from',
      );
    }
    final fromPath = fs.pathContext.join(syncRoot, fromRel);
    if (!(await fs.stat(fromPath)).isDirectory) {
      return SkillStepResult(
        success: false,
        message: 'fs.materialize source missing: $fromPath',
      );
    }
    final toPath = ctx.resolve(toTemplate);
    if (toPath.isEmpty) {
      return const SkillStepResult(
        success: false,
        message: 'fs.materialize to path resolved empty',
      );
    }
    await fs.ensureDir(fs.pathContext.dirname(toPath));
    await fs.removeRecursive(toPath);
    if (mode == 'copy') {
      await fs.copyTree(source: fromPath, destination: toPath);
    } else {
      final ok = await fs.createSymlink(target: fromPath, linkPath: toPath);
      if (!ok) {
        return SkillStepResult(
          success: false,
          message: 'Failed to link $fromPath → $toPath',
        );
      }
    }
    ctx.packBin ??= toPath;
    if (!ctx.pathExports.contains(toPath)) {
      ctx.pathExports.add(toPath);
    }
    return SkillStepResult.ok;
  }

  Future<SkillStepResult> _handleScriptRun(
    SkillInstallStep step,
    SkillAcquireContext ctx,
  ) async {
    if (!_isLocalAcquireSupported()) {
      return const SkillStepResult(
        success: false,
        message: 'Script skill install is not supported on this host.',
      );
    }

    final commandRaw = step.withArgs['command'];
    final package = (step.withArgs['package'] as String?)?.trim();
    final cwdTemplate = (step.withArgs['cwd'] as String?)?.trim();
    final cwd = cwdTemplate == null || cwdTemplate.isEmpty
        ? ctx.syncRoot
        : ctx.resolve(cwdTemplate);

    if (commandRaw is List && commandRaw.isNotEmpty) {
      final args = commandRaw.map((e) => e.toString()).toList(growable: false);
      final script = cwd == null || cwd.isEmpty
          ? args.map(_shellQuote).join(' ')
          : 'cd ${_shellQuote(cwd)} && ${args.map(_shellQuote).join(' ')}';
      final result = await _runner(CliInstallerCommand.unixShellScript(script));
      if (result.exitCode != 0) {
        return SkillStepResult(
          success: false,
          message: result.stderr.trim().isNotEmpty
              ? result.stderr.trim()
              : result.stdout.trim().isNotEmpty
              ? result.stdout.trim()
              : 'script.run failed',
        );
      }
      return SkillStepResult.ok;
    }

    // HTTPS installers: curl|sh, then register primary / new skill dir.
    if (package == null || package.isEmpty) {
      return const SkillStepResult(
        success: false,
        message: 'script.run requires command or package URL',
      );
    }
    if (!_isSafeScriptUrl(package)) {
      return const SkillStepResult(
        success: false,
        message: 'Unsafe script URL',
      );
    }
    final alternatives = step.withArgs['alternatives'];
    final urls = <String>[
      package,
      if (alternatives is List)
        for (final a in alternatives)
          if (a.toString().contains(':'))
            a.toString().substring(a.toString().indexOf(':') + 1)
          else
            a.toString(),
    ];
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
      return SkillStepResult(
        success: false,
        message: last?.stderr.trim().isNotEmpty == true
            ? last!.stderr.trim()
            : 'Installation failed.',
      );
    }

    final after = await _listSkillDirsWithSkillMd();
    final newDirs = after.difference(before).toList()..sort();
    final primary = (step.withArgs['primaryDirectory'] as String?)?.trim();
    final id =
        (step.withArgs['id'] as String?)?.trim() ?? ctx.expectedSkillId;
    String? chosen;
    if (newDirs.isEmpty) {
      if (primary != null && after.contains(primary)) {
        chosen = primary;
      } else {
        return const SkillStepResult(
          success: false,
          message:
              'Install command succeeded but no SKILL.md was found under '
              'skills/installed/.',
        );
      }
    } else if (newDirs.length == 1) {
      chosen = newDirs.single;
    } else if (primary != null && newDirs.contains(primary)) {
      chosen = primary;
    } else {
      return SkillStepResult(
        success: false,
        message:
            'Multiple new skill directories appeared (${newDirs.join(', ')}); '
            'set primaryDirectory.',
      );
    }
    try {
      await _registerDirectory(id: id, directory: chosen!);
      if (!ctx.installedSkillIds.contains(id)) {
        ctx.installedSkillIds.add(id);
      }
      return SkillStepResult.ok;
    } catch (e) {
      return SkillStepResult(success: false, message: e.toString());
    }
  }

  static bool _isSafeScriptUrl(String url) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) return false;
    const banned = r'''\s'"\$\\;`|&<>()''';
    return !RegExp('[$banned]').hasMatch(url);
  }

  static String _shellQuote(String value) => "'${value.replaceAll("'", "'\\''")}'";
}
