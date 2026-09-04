import 'dart:convert';
import 'dart:typed_data';

import '../../../models/discoverable_team.dart';
import '../../../models/skill.dart';
import '../../../repositories/skill_repository.dart';
import '../../../repositories/workspace_project_config_repository.dart';
import '../../io/filesystem.dart';
import '../../skill/skill_acquisition_engine.dart';
import '../../skill/skill_fetch_service.dart';
import '../../skill/skill_install_service.dart';
import '../../storage/app_storage.dart';
import '../catalog_kind.dart';
import '../catalog_mcp_constants.dart';
import '../catalog_mutation_bus.dart';
import '../catalog_path_sandbox.dart';
import '../catalog_workspace_binder.dart';
import 'skill_catalog_tools.dart';

class SkillCatalogModule implements CatalogKindModule {
  SkillCatalogModule({
    required this.repository,
    required this.install,
    required this.binder,
    required this.bus,
    this.engine,
    this.search,
    this.onDeleted,
    WorkspaceProjectConfigRepository? workspaceConfig,
  }) : _workspaceConfig = workspaceConfig ?? binder.repo;

  final SkillRepository repository;
  final SkillInstallService install;
  final CatalogWorkspaceBinder binder;
  final CatalogMutationBus bus;
  final SkillAcquisitionEngine? engine;
  final Future<List<Map<String, Object?>>> Function(String query)? search;
  final Future<void> Function(String skillId)? onDeleted;
  final WorkspaceProjectConfigRepository _workspaceConfig;

  @override
  String get kind => 'skill';

  @override
  bool get supportsCreate => true;

  @override
  bool get supportsImport => true;

  @override
  bool get supportsInstall => true;

  @override
  List<CatalogToolSpec> advertise() => skillCatalogTools;

  @override
  Future<CatalogResult> handle(CatalogOp op, CatalogRequest req) {
    return switch (op) {
      CatalogOp.search => _search(req),
      CatalogOp.list => _list(req),
      CatalogOp.read => _read(req),
      CatalogOp.install => _install(req),
      CatalogOp.importPath => _import(req),
      CatalogOp.create => _create(req),
      CatalogOp.update => _update(req),
      CatalogOp.unbind => _unbind(req),
      CatalogOp.delete => _delete(req),
    };
  }

  Future<CatalogResult> _search(CatalogRequest req) async {
    final query = _string(req.arguments['query']) ?? '';
    final hits = search == null
        ? const <Map<String, Object?>>[]
        : await search!(query);
    return CatalogResult.ok(
      kind: kind,
      ids: const [],
      workspaceId: req.workspaceId,
      restartRequired: false,
      data: {'results': hits},
    );
  }

  Future<CatalogResult> _list(CatalogRequest req) async {
    final installed = await repository.loadInstalled();
    final bound = (await _workspaceConfig.load(
      req.workspaceId,
    )).bundle.skillIds;
    return CatalogResult.ok(
      kind: kind,
      ids: [for (final s in installed) s.id],
      workspaceId: req.workspaceId,
      restartRequired: false,
      data: {
        'skill': {
          'installed': [for (final s in installed) s.toJson()],
          'boundIds': bound,
        },
      },
    );
  }

  Future<CatalogResult> _read(CatalogRequest req) async {
    final skill = await _requireInstalled(_requireId(req));
    final fs = AppStorage.fs;
    final ctx = fs.pathContext;
    final dir = ctx.join(
      await repository.manifest.resolveSkillsDir(),
      skill.directory,
    );
    final skillMd = await fs.readString(ctx.join(dir, 'SKILL.md')) ?? '';
    final files = <String>[];
    for (final entry in await fs.listDirRecursive(dir)) {
      if (!entry.isDirectory) files.add(entry.name);
    }
    return CatalogResult.ok(
      kind: kind,
      ids: [skill.id],
      workspaceId: req.workspaceId,
      restartRequired: false,
      data: {
        'id': skill.id,
        'name': skill.name,
        'description': skill.description,
        'skillMd': skillMd,
        'files': files,
      },
    );
  }

  Future<CatalogResult> _install(CatalogRequest req) async {
    final installed = await repository.loadInstalled();
    final existing = _existingForInstall(installed, req.arguments);
    if (existing != null) {
      return _finishWrite(CatalogOp.install, req, [existing.id]);
    }

    final ref = _refFromArgs(req.arguments);
    if (engine != null) {
      final acquired = await engine!.install(ref, overwrite: req.overwrite);
      if (!acquired.success) {
        final unsafe = acquired.message.contains('unsafe script URL');
        throw CatalogException(
          unsafe ? 'unsafe_script_url' : 'install_failed',
          acquired.message,
        );
      }
      final ids = acquired.installedSkillIds.isNotEmpty
          ? acquired.installedSkillIds
          : [
              if (acquired.skillId != null && acquired.skillId!.isNotEmpty)
                acquired.skillId!,
            ];
      if (ids.isEmpty) {
        throw CatalogException(
          'install_failed',
          acquired.message.isEmpty
              ? 'Install produced no skill id'
              : acquired.message,
        );
      }
      return _finishWrite(CatalogOp.install, req, ids);
    }

    if (ref.repoOwner.isEmpty ||
        ref.repoName.isEmpty ||
        ref.directory.isEmpty) {
      throw CatalogException(
        'not_found',
        'Skill is not installed and no install source was provided',
      );
    }
    final skill = await repository.installFromDiscovery(
      ref.toDiscoverableSkill(),
      overwrite: req.overwrite,
    );
    return _finishWrite(CatalogOp.install, req, [skill.id]);
  }

  Future<CatalogResult> _import(CatalogRequest req) async {
    final path = _string(req.arguments['path'])?.trim() ?? '';
    if (path.isEmpty) {
      throw CatalogException('not_found', 'import_skill requires path');
    }
    await assertSafeImportPath(
      fs: req.workFs,
      path: path,
      allowedRoots: req.allowedRoots,
    );

    final roots = await _discoverSkillRoots(req.workFs, path);
    if (roots.isEmpty) {
      throw CatalogException('no_skill_md', 'No SKILL.md found at $path');
    }

    final ids = <String>[];
    final failed = <CatalogFailure>[];
    for (final root in roots) {
      try {
        ids.add(await _installFromWorkTree(req, root));
      } on CatalogException catch (e) {
        failed.add(
          CatalogFailure(path: root, code: e.code, message: e.message),
        );
      } on SkillInstallException catch (e) {
        failed.add(
          CatalogFailure(
            path: root,
            code: 'already_exists',
            message: e.message,
          ),
        );
      } on SkillParseException catch (e) {
        failed.add(
          CatalogFailure(
            path: root,
            code: 'invalid_skill_md',
            message: e.message,
          ),
        );
      } catch (e) {
        failed.add(
          CatalogFailure(path: root, code: 'install_failed', message: '$e'),
        );
      }
    }

    if (ids.isEmpty && failed.isNotEmpty) {
      throw CatalogException(failed.first.code, failed.first.message);
    }
    return _finishWrite(
      CatalogOp.importPath,
      req,
      ids,
      failed: failed.isEmpty ? null : failed,
    );
  }

  Future<CatalogResult> _create(CatalogRequest req) async {
    final name = _string(req.arguments['name'])?.trim() ?? '';
    final body = _string(req.arguments['body']);
    if (name.isEmpty || body == null) {
      throw CatalogException(
        'invalid_args',
        'create_skill requires name and body',
      );
    }
    final description = _string(req.arguments['description']) ?? '';
    final directoryArg = _string(req.arguments['directory'])?.trim() ?? '';
    final directory = directoryArg.isEmpty ? _slug(name) : directoryArg;
    assertSafeCatalogEntryName(directory, field: 'directory');
    final files = <String, Uint8List>{};
    _mergeStringFiles(files, req.arguments['files']);
    files['SKILL.md'] = Uint8List.fromList(
      utf8.encode(_skillMd(name: name, description: description, body: body)),
    );
    final skill = await install.installLocal(
      basename: directory,
      files: files,
      repoOwner: null,
      repoName: null,
      repoBranch: null,
      readmeUrl: null,
      name: name,
      description: description,
      overwrite: req.overwrite,
    );
    return _finishWrite(CatalogOp.create, req, [skill.id]);
  }

  Future<CatalogResult> _update(CatalogRequest req) async {
    final skill = await _requireInstalled(_requireId(req));
    final files = await _collectFiles(
      AppStorage.fs,
      AppStorage.fs.pathContext.join(
        await repository.manifest.resolveSkillsDir(),
        skill.directory,
      ),
    );
    _mergeStringFiles(files, req.arguments['files']);
    final body = _string(req.arguments['body']);
    final name = _string(req.arguments['name'])?.trim() ?? skill.name;
    final description =
        _string(req.arguments['description']) ?? skill.description;
    if (body != null) {
      files['SKILL.md'] = Uint8List.fromList(
        utf8.encode(_skillMd(name: name, description: description, body: body)),
      );
    }
    if (!files.containsKey('SKILL.md')) {
      throw CatalogException('not_found', 'Skill is missing SKILL.md');
    }
    final updated = await install.installLocal(
      basename: skill.directory,
      files: files,
      repoOwner: skill.repoOwner,
      repoName: skill.repoName,
      repoBranch: skill.repoBranch,
      readmeUrl: skill.readmeUrl,
      name: name,
      description: description,
      overwrite: true,
      idOverride: skill.id,
    );
    return _finishWrite(CatalogOp.update, req, [updated.id]);
  }

  Future<CatalogResult> _unbind(CatalogRequest req) async {
    final id = _requireId(req);
    await _unbindIds(req, [id]);
    _emit(CatalogOp.unbind, req, [id]);
    return CatalogResult.ok(
      kind: kind,
      ids: [id],
      workspaceId: req.workspaceId,
      boundTo: req.bindTo,
      message: catalogWriteSuccessMessage,
    );
  }

  Future<CatalogResult> _delete(CatalogRequest req) async {
    final skill = await _requireInstalled(_requireId(req));
    await repository.uninstall(skill);
    await onDeleted?.call(skill.id);
    await _unbindIds(req, [skill.id]);
    _emit(CatalogOp.delete, req, [skill.id]);
    return CatalogResult.ok(
      kind: kind,
      ids: [skill.id],
      workspaceId: req.workspaceId,
      boundTo: req.bindTo,
      message: catalogWriteSuccessMessage,
    );
  }

  Future<CatalogResult> _finishWrite(
    CatalogOp op,
    CatalogRequest req,
    List<String> ids, {
    List<CatalogFailure>? failed,
  }) async {
    await _bindIds(req, ids);
    _emit(op, req, ids);
    if (failed != null && failed.isNotEmpty) {
      return CatalogResult.partial(
        kind: kind,
        ids: ids,
        workspaceId: req.workspaceId,
        failed: failed,
        boundTo: req.bindTo,
        message: catalogWriteSuccessMessage,
      );
    }
    return CatalogResult.ok(
      kind: kind,
      ids: ids,
      workspaceId: req.workspaceId,
      boundTo: req.bindTo,
      message: catalogWriteSuccessMessage,
    );
  }

  Future<void> _bindIds(CatalogRequest req, List<String> ids) {
    if (req.bindTo == CatalogBindTo.team) return Future.value();
    return binder.bindIds(
      workspaceId: req.workspaceId,
      bindTo: req.bindTo,
      apply: (current) {
        for (final id in ids) {
          current.skillIds.add(id);
        }
      },
    );
  }

  Future<void> _unbindIds(CatalogRequest req, List<String> ids) {
    return binder.unbindIds(
      workspaceId: req.workspaceId,
      bindTo: req.bindTo,
      apply: (current) {
        current.skillIds.removeWhere(ids.contains);
      },
    );
  }

  void _emit(CatalogOp op, CatalogRequest req, List<String> ids) {
    bus.emit(
      CatalogMutationEvent(
        kind: kind,
        op: op,
        ids: ids,
        workspaceId: req.workspaceId,
      ),
    );
  }

  Future<Skill> _requireInstalled(String id) async {
    final skill = _find(await repository.loadInstalled(), id);
    if (skill == null) {
      throw CatalogException('not_found', 'Skill not installed: $id');
    }
    return skill;
  }

  Skill? _existingForInstall(
    List<Skill> installed,
    Map<String, Object?> arguments,
  ) {
    final id = _string(arguments['id'])?.trim();
    if (id != null && id.isNotEmpty) {
      final match = _find(installed, id);
      if (match != null) return match;
    }
    final key = _string(arguments['key'])?.trim();
    if (key != null && key.isNotEmpty) {
      final match = _find(installed, key);
      if (match != null) return match;
    }
    return _find(installed, _refFromArgs(arguments).expectedLocalId);
  }

  Future<String> _installFromWorkTree(CatalogRequest req, String root) async {
    final files = await _collectFiles(req.workFs, root);
    final skillMd = files['SKILL.md'];
    if (skillMd == null) {
      throw CatalogException('no_skill_md', 'No SKILL.md in $root');
    }
    final fm = parseSkillFrontmatter(utf8.decode(skillMd));
    final basename = req.workFs.pathContext.basename(root);
    final skill = await install.installLocal(
      basename: basename,
      files: files,
      repoOwner: null,
      repoName: null,
      repoBranch: null,
      readmeUrl: null,
      name: fm.name,
      description: fm.description,
      overwrite: req.overwrite,
    );
    return skill.id;
  }

  Future<List<String>> _discoverSkillRoots(Filesystem fs, String path) async {
    final ctx = fs.pathContext;
    final direct = ctx.join(path, 'SKILL.md');
    if ((await fs.stat(direct)).isFile) return [path];

    final children = await _skillDirsIn(fs, path);
    if (children.isNotEmpty) return children;

    return _skillDirsIn(fs, ctx.join(path, 'skills'));
  }

  Future<List<String>> _skillDirsIn(Filesystem fs, String path) async {
    if (!(await fs.stat(path)).isDirectory) return const [];
    final ctx = fs.pathContext;
    final roots = <String>[];
    for (final entry in await fs.listDir(path)) {
      if (!entry.isDirectory) continue;
      final child = ctx.join(path, entry.name);
      if ((await fs.stat(ctx.join(child, 'SKILL.md'))).isFile) {
        roots.add(child);
      }
    }
    return roots;
  }

  Future<Map<String, Uint8List>> _collectFiles(
    Filesystem fs,
    String root,
  ) async {
    final ctx = fs.pathContext;
    final files = <String, Uint8List>{};
    for (final entry in await fs.listDirRecursive(root)) {
      if (entry.isDirectory) continue;
      final bytes = await fs.readBytes(ctx.join(root, entry.name));
      if (bytes == null) continue;
      files[entry.name] = Uint8List.fromList(bytes);
    }
    return files;
  }

  static Skill? _find(List<Skill> installed, String id) {
    for (final skill in installed) {
      if (skill.id == id) return skill;
    }
    return null;
  }

  static String _requireId(CatalogRequest req) {
    final id = _string(req.arguments['id'])?.trim() ?? '';
    if (id.isEmpty) {
      throw CatalogException('invalid_args', 'id is required');
    }
    return id;
  }

  static SkillDependencyRef _refFromArgs(Map<String, Object?> args) {
    var owner = _string(args['repoOwner']) ?? '';
    var repoName = _string(args['repoName']) ?? '';
    final repo = _string(args['repo']) ?? '';
    if (owner.isEmpty && repo.contains('/')) {
      final slash = repo.indexOf('/');
      owner = repo.substring(0, slash);
      repoName = repo.substring(slash + 1);
    }
    return SkillDependencyRef(
      repoOwner: owner,
      repoName: repoName,
      repoBranch:
          _string(args['branch']) ?? _string(args['repoBranch']) ?? 'main',
      directory: _string(args['directory']) ?? '',
      name: _string(args['name']) ?? '',
      id: _string(args['id']),
      packId: _string(args['packId']),
      scriptUrl: _string(args['script_url']) ?? _string(args['scriptUrl']),
    );
  }

  static void _mergeStringFiles(Map<String, Uint8List> files, Object? raw) {
    if (raw is! Map) return;
    for (final entry in raw.entries) {
      final value = entry.value;
      if (value is! String) continue;
      final key = entry.key.toString();
      assertSafeCatalogEntryName(key, field: 'files');
      files[key] = Uint8List.fromList(utf8.encode(value));
    }
  }

  static String _skillMd({
    required String name,
    required String description,
    required String body,
  }) {
    if (body.trimLeft().startsWith('---')) return body;
    return '---\nname: $name\ndescription: $description\n---\n$body';
  }

  static String _slug(String name) {
    final slug = name
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return slug.isEmpty ? 'skill' : slug;
  }

  static String? _string(Object? value) => value is String ? value : null;
}
