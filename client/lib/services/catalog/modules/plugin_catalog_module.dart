import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../models/plugin.dart';
import '../../../repositories/plugin_repository.dart';
import '../../../repositories/workspace_project_config_repository.dart';
import '../../io/filesystem.dart';
import '../../plugin/plugin_exceptions.dart';
import '../../plugin/plugin_install_service.dart';
import '../../storage/app_storage.dart';
import '../catalog_kind.dart';
import '../catalog_mcp_constants.dart';
import '../catalog_mutation_bus.dart';
import '../catalog_path_sandbox.dart';
import '../catalog_workspace_binder.dart';
import 'plugin_catalog_tools.dart';

class PluginCatalogModule implements CatalogKindModule {
  PluginCatalogModule({
    required this.repository,
    required this.install,
    required this.binder,
    required this.bus,
    this.search,
    this.installFromDiscovery,
    this.onDeleted,
    WorkspaceProjectConfigRepository? workspaceConfig,
  }) : _workspaceConfig = workspaceConfig ?? binder.repo;

  final PluginRepository repository;
  final PluginInstallService install;
  final CatalogWorkspaceBinder binder;
  final CatalogMutationBus bus;
  final Future<List<Map<String, Object?>>> Function(String query)? search;
  final Future<Plugin> Function(Map<String, Object?> arguments)?
  installFromDiscovery;
  final Future<void> Function(String pluginId)? onDeleted;
  final WorkspaceProjectConfigRepository _workspaceConfig;

  static const _manifestRelPaths = [
    'plugin.json',
    '.claude-plugin/plugin.json',
    '.plugin/plugin.json',
  ];

  @override
  String get kind => 'plugin';

  @override
  bool get supportsCreate => false;

  @override
  bool get supportsImport => true;

  @override
  bool get supportsInstall => true;

  @override
  List<CatalogToolSpec> advertise() => pluginCatalogTools;

  @override
  Future<CatalogResult> handle(CatalogOp op, CatalogRequest req) {
    return switch (op) {
      CatalogOp.search => _search(req),
      CatalogOp.list => _list(req),
      CatalogOp.read => _read(req),
      CatalogOp.install => _install(req),
      CatalogOp.importPath => _import(req),
      CatalogOp.create => Future.error(
        CatalogException('unsupported_op', 'create_plugin is not supported'),
      ),
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
    final installed = await repository.loadAll();
    final bound = (await _workspaceConfig.load(
      req.workspaceId,
    )).bundle.pluginIds;
    return CatalogResult.ok(
      kind: kind,
      ids: [for (final plugin in installed) plugin.id],
      workspaceId: req.workspaceId,
      restartRequired: false,
      data: {
        'plugin': {
          'installed': [for (final plugin in installed) plugin.toJson()],
          'boundIds': bound,
        },
      },
    );
  }

  Future<CatalogResult> _read(CatalogRequest req) async {
    final plugin = await _requireInstalled(_requireId(req));
    final fs = AppStorage.fs;
    final ctx = fs.pathContext;
    final dir = ctx.join(_pluginsRoot(), plugin.directory);
    final files = <String>[];
    if ((await fs.stat(dir)).isDirectory) {
      for (final entry in await fs.listDirRecursive(dir)) {
        if (!entry.isDirectory) files.add(entry.name);
      }
    }
    return CatalogResult.ok(
      kind: kind,
      ids: [plugin.id],
      workspaceId: req.workspaceId,
      restartRequired: false,
      data: {...plugin.toJson(), 'files': files},
    );
  }

  Future<CatalogResult> _install(CatalogRequest req) async {
    final installed = await repository.loadAll();
    final existing = _existingForInstall(installed, req.arguments);
    if (existing != null) {
      return _finishWrite(CatalogOp.install, req, [existing.id]);
    }
    final installFn = installFromDiscovery;
    if (installFn == null) {
      throw CatalogException(
        'not_found',
        'Plugin is not installed and no install source was provided',
      );
    }
    try {
      final plugin = await installFn(req.arguments);
      return await _finishWrite(CatalogOp.install, req, [plugin.id]);
    } on CatalogException {
      rethrow;
    } on PluginException catch (e) {
      throw CatalogException('install_failed', e.message);
    } catch (e) {
      throw CatalogException('install_failed', '$e');
    }
  }

  Future<CatalogResult> _import(CatalogRequest req) async {
    final path = _string(req.arguments['path'])?.trim() ?? '';
    if (path.isEmpty) {
      throw CatalogException('not_found', 'import_plugin requires path');
    }
    await assertSafeImportPath(
      fs: req.workFs,
      path: path,
      allowedRoots: req.allowedRoots,
    );

    final roots = await _discoverPluginRoots(req.workFs, path);
    if (roots.isEmpty) {
      if (await _hasSkillMd(req.workFs, path)) {
        throw CatalogException(
          'wrong_kind',
          'Path looks like a skill. Use import_skill instead.',
        );
      }
      throw CatalogException(
        'not_found',
        'No plugin.json or .claude-plugin/plugin.json found at $path',
      );
    }

    final ids = <String>[];
    final failed = <CatalogFailure>[];
    for (final root in roots) {
      try {
        ids.add(await _installFromWorkTree(req.workFs, root));
      } on CatalogException catch (e) {
        failed.add(
          CatalogFailure(path: root, code: e.code, message: e.message),
        );
      } on PluginException catch (e) {
        failed.add(
          CatalogFailure(
            path: root,
            code: 'install_failed',
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

  Future<CatalogResult> _update(CatalogRequest req) async {
    final plugin = await _requireInstalled(_requireId(req));
    final path = _string(req.arguments['path'])?.trim() ?? '';
    if (path.isNotEmpty) {
      await assertSafeImportPath(
        fs: req.workFs,
        path: path,
        allowedRoots: req.allowedRoots,
      );
      if (!await _hasPluginLayout(req.workFs, path)) {
        throw CatalogException(
          'not_found',
          'No plugin.json or .claude-plugin/plugin.json found at $path',
        );
      }
      final updated = await _withStagedPlugin(
        req.workFs,
        path,
        (staged) => install.updateInPlace(plugin, staged),
      );
      return _finishWrite(CatalogOp.update, req, [updated.id]);
    }
    final updated = await repository.updatePlugin(plugin);
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
    final plugin = await _requireInstalled(_requireId(req));
    await repository.uninstall(plugin);
    await onDeleted?.call(plugin.id);
    await _unbindIds(req, [plugin.id]);
    _emit(CatalogOp.delete, req, [plugin.id]);
    return CatalogResult.ok(
      kind: kind,
      ids: [plugin.id],
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
    return binder.bindIds(
      workspaceId: req.workspaceId,
      bindTo: req.bindTo,
      apply: (current) {
        for (final id in ids) {
          current.pluginIds.add(id);
        }
      },
    );
  }

  Future<void> _unbindIds(CatalogRequest req, List<String> ids) {
    return binder.unbindIds(
      workspaceId: req.workspaceId,
      bindTo: req.bindTo,
      apply: (current) {
        current.pluginIds.removeWhere(ids.contains);
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

  Future<Plugin> _requireInstalled(String id) async {
    final plugin = await repository.findById(id);
    if (plugin == null) {
      throw CatalogException('not_found', 'Plugin not installed: $id');
    }
    return plugin;
  }

  Plugin? _existingForInstall(
    List<Plugin> installed,
    Map<String, Object?> arguments,
  ) {
    final id = _string(arguments['id'])?.trim();
    if (id != null && id.isNotEmpty) {
      final match = _find(installed, id);
      if (match != null) return match;
    }
    final key = _string(arguments['key'])?.trim();
    if (key != null && key.isNotEmpty) {
      return _find(installed, key);
    }
    return null;
  }

  Future<String> _installFromWorkTree(Filesystem fs, String root) {
    return _withStagedPlugin(
      fs,
      root,
      (staged) async => (await install.installFromDirectory(staged)).id,
    );
  }

  Future<T> _withStagedPlugin<T>(
    Filesystem fs,
    String root,
    Future<T> Function(Directory staged) run,
  ) async {
    final ctx = fs.pathContext;
    final basename = ctx.basename(root);
    assertSafeCatalogEntryName(basename, field: 'path');
    final parent = Directory.systemTemp.createTempSync('catalog-plugin-');
    try {
      final staged = Directory(p.join(parent.path, basename))..createSync();
      await _copyWorkTree(fs, root, staged);
      _promoteRootPluginJson(staged);
      return await run(staged);
    } finally {
      if (parent.existsSync()) parent.deleteSync(recursive: true);
    }
  }

  Future<void> _copyWorkTree(Filesystem fs, String root, Directory dest) async {
    final ctx = fs.pathContext;
    for (final entry in await fs.listDirRecursive(root)) {
      _assertSafeRelative(ctx, entry.name);
      final destPath = p.normalize(p.join(dest.path, entry.name));
      if (entry.isDirectory) {
        Directory(destPath).createSync(recursive: true);
        continue;
      }
      Directory(p.dirname(destPath)).createSync(recursive: true);
      final bytes = await fs.readBytes(ctx.join(root, entry.name));
      if (bytes == null) continue;
      File(destPath).writeAsBytesSync(bytes);
    }
  }

  static void _promoteRootPluginJson(Directory staged) {
    final rootJson = File(p.join(staged.path, 'plugin.json'));
    if (!rootJson.existsSync()) return;
    final recognized = [
      File(p.join(staged.path, '.claude-plugin', 'plugin.json')),
      File(p.join(staged.path, '.plugin', 'plugin.json')),
    ];
    if (recognized.any((f) => f.existsSync())) return;
    final target = File(p.join(staged.path, '.plugin', 'plugin.json'));
    target.parent.createSync(recursive: true);
    rootJson.copySync(target.path);
  }

  Future<List<String>> _discoverPluginRoots(Filesystem fs, String path) async {
    if (await _hasPluginLayout(fs, path)) return [path];
    if (!(await fs.stat(path)).isDirectory) return const [];
    final ctx = fs.pathContext;
    final roots = <String>[];
    for (final entry in await fs.listDir(path)) {
      if (!entry.isDirectory) continue;
      final child = ctx.join(path, entry.name);
      if (await _hasPluginLayout(fs, child)) roots.add(child);
    }
    return roots;
  }

  Future<bool> _hasPluginLayout(Filesystem fs, String dir) async {
    final ctx = fs.pathContext;
    for (final rel in _manifestRelPaths) {
      if ((await fs.stat(ctx.join(dir, rel))).isFile) return true;
    }
    return false;
  }

  Future<bool> _hasSkillMd(Filesystem fs, String dir) async {
    return (await fs.stat(fs.pathContext.join(dir, 'SKILL.md'))).isFile;
  }

  static void _assertSafeRelative(p.Context ctx, String rel) {
    for (final part in ctx.split(rel)) {
      if (part.isEmpty || part == '.') continue;
      assertSafeCatalogEntryName(part, field: 'path');
    }
  }

  String _pluginsRoot() {
    if (AppStorage.isInstalled) return AppStorage.context.pluginsRoot;
    return AppPaths.pluginsDirForTeampilotRoot(AppStorage.paths.basePath);
  }

  static Plugin? _find(List<Plugin> installed, String id) {
    for (final plugin in installed) {
      if (plugin.id == id) return plugin;
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

  static String? _string(Object? value) => value is String ? value : null;
}
