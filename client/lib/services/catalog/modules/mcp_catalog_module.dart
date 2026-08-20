import 'dart:convert';

import '../../../models/mcp_server.dart';
import '../../../repositories/mcp_repository.dart';
import '../../../repositories/workspace_project_config_repository.dart';
import '../../mcp/mcp_catalog_mapper.dart';
import '../catalog_kind.dart';
import '../catalog_mutation_bus.dart';
import '../catalog_path_sandbox.dart';
import '../catalog_workspace_binder.dart';
import 'mcp_catalog_tools.dart';

class McpCatalogModule implements CatalogKindModule {
  McpCatalogModule({
    required this.repository,
    required this.binder,
    required this.bus,
    this.draftFromListing,
    this.search,
    WorkspaceProjectConfigRepository? workspaceConfig,
  }) : _workspaceConfig = workspaceConfig ?? binder.repo;

  final McpRepository repository;
  final CatalogWorkspaceBinder binder;
  final CatalogMutationBus bus;
  final Future<McpServer> Function(String listingId)? draftFromListing;
  final Future<List<Map<String, Object?>>> Function(String query)? search;
  final WorkspaceProjectConfigRepository _workspaceConfig;

  @override
  String get kind => 'mcp';

  @override
  bool get supportsCreate => true;

  @override
  bool get supportsImport => true;

  @override
  bool get supportsInstall => true;

  @override
  List<CatalogToolSpec> advertise() => mcpCatalogTools;

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
    final installed = await repository.loadAll();
    final bound = (await _workspaceConfig.load(
      req.workspaceId,
    )).bundle.mcpServerIds;
    return CatalogResult.ok(
      kind: kind,
      ids: [for (final server in installed) server.id],
      workspaceId: req.workspaceId,
      restartRequired: false,
      data: {
        'mcp': {
          'installed': [for (final server in installed) _redactedJson(server)],
          'boundIds': bound,
        },
      },
    );
  }

  Future<CatalogResult> _read(CatalogRequest req) async {
    final server = await _requireInstalled(_requireId(req));
    return CatalogResult.ok(
      kind: kind,
      ids: [server.id],
      workspaceId: req.workspaceId,
      restartRequired: false,
      data: _redactedJson(server),
    );
  }

  Future<CatalogResult> _install(CatalogRequest req) async {
    final existing = await _existingForInstall(req.arguments);
    if (existing != null) {
      return _finishWrite(CatalogOp.install, req, [existing.id]);
    }
    final listingId =
        _string(req.arguments['id'])?.trim() ??
        _string(req.arguments['key'])?.trim() ??
        '';
    final draftFn = draftFromListing;
    if (listingId.isEmpty || draftFn == null) {
      throw CatalogException(
        'not_found',
        'MCP server is not installed and no listing draft was provided',
      );
    }
    final draft = await draftFn(listingId);
    final now = DateTime.now().millisecondsSinceEpoch;
    final saved = await _upsert(
      draft.copyWith(
        createdAt: draft.createdAt == 0 ? now : draft.createdAt,
        updatedAt: now,
      ),
    );
    return _finishWrite(CatalogOp.install, req, [saved.id]);
  }

  Future<CatalogResult> _import(CatalogRequest req) async {
    final path = _string(req.arguments['path'])?.trim() ?? '';
    if (path.isEmpty) {
      throw CatalogException('not_found', 'import_mcp requires path');
    }
    await assertSafeImportPath(
      fs: req.workFs,
      path: path,
      allowedRoots: req.allowedRoots,
    );

    final text = await req.workFs.readString(path);
    if (text == null || text.trim().isEmpty) {
      throw CatalogException('not_found', 'No MCP JSON at $path');
    }
    late final Object decoded;
    try {
      decoded = jsonDecode(text);
    } catch (e) {
      throw CatalogException('invalid_args', 'Invalid MCP JSON: $e');
    }
    final specs = _serversFromJson(decoded);
    if (specs.isEmpty) {
      throw CatalogException('not_found', 'No MCP servers in $path');
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    final ids = <String>[];
    for (final entry in specs.entries) {
      final id = McpCatalogMapper.sanitizeId(entry.key);
      final saved = await _upsert(
        McpServer(
          id: id.isEmpty ? entry.key : id,
          name: entry.key,
          server: entry.value,
          source: McpServerSource.imported,
          importedFrom: path,
          createdAt: now,
          updatedAt: now,
        ),
      );
      ids.add(saved.id);
    }
    return _finishWrite(CatalogOp.importPath, req, ids);
  }

  Future<CatalogResult> _create(CatalogRequest req) async {
    final name = _string(req.arguments['name'])?.trim() ?? '';
    if (name.isEmpty) {
      throw CatalogException('invalid_args', 'create_mcp requires name');
    }
    final server = _serverSpecFromArgs(req.arguments, requireCommand: true);
    final idArg = _string(req.arguments['id'])?.trim() ?? '';
    final id = idArg.isNotEmpty ? idArg : McpCatalogMapper.sanitizeId(name);
    final now = DateTime.now().millisecondsSinceEpoch;
    final saved = await _upsert(
      McpServer(
        id: id.isEmpty ? name : id,
        name: name,
        server: server,
        createdAt: now,
        updatedAt: now,
      ),
    );
    return _finishWrite(CatalogOp.create, req, [saved.id]);
  }

  Future<CatalogResult> _update(CatalogRequest req) async {
    final existing = await _requireInstalled(_requireId(req));
    final server = Map<String, Object?>.from(existing.server);
    final overlay = req.arguments['server'];
    if (overlay is Map) {
      server.addAll(overlay.cast<String, Object?>());
    }
    server.addAll(_serverSpecFromArgs(req.arguments, requireCommand: false));
    final name = _string(req.arguments['name'])?.trim() ?? existing.name;
    final now = DateTime.now().millisecondsSinceEpoch;
    final saved = await _upsert(
      existing.copyWith(name: name, server: server, updatedAt: now),
    );
    return _finishWrite(CatalogOp.update, req, [saved.id]);
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
    );
  }

  Future<CatalogResult> _delete(CatalogRequest req) async {
    final server = await _requireInstalled(_requireId(req));
    await repository.deleteById(server.id);
    await _unbindIds(req, [server.id]);
    _emit(CatalogOp.delete, req, [server.id]);
    return CatalogResult.ok(
      kind: kind,
      ids: [server.id],
      workspaceId: req.workspaceId,
      boundTo: req.bindTo,
    );
  }

  Future<CatalogResult> _finishWrite(
    CatalogOp op,
    CatalogRequest req,
    List<String> ids,
  ) async {
    await _bindIds(req, ids);
    _emit(op, req, ids);
    return CatalogResult.ok(
      kind: kind,
      ids: ids,
      workspaceId: req.workspaceId,
      boundTo: req.bindTo,
    );
  }

  Future<void> _bindIds(CatalogRequest req, List<String> ids) {
    return binder.bindIds(
      workspaceId: req.workspaceId,
      bindTo: req.bindTo,
      apply: (current) {
        for (final id in ids) {
          current.mcpServerIds.add(id);
        }
      },
    );
  }

  Future<void> _unbindIds(CatalogRequest req, List<String> ids) {
    return binder.unbindIds(
      workspaceId: req.workspaceId,
      bindTo: req.bindTo,
      apply: (current) {
        current.mcpServerIds.removeWhere(ids.contains);
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

  Future<McpServer> _upsert(McpServer server) async {
    try {
      return await repository.upsert(server);
    } on McpValidationException catch (e) {
      throw CatalogException('invalid_args', e.toString());
    }
  }

  Future<McpServer> _requireInstalled(String id) async {
    final server = await repository.findById(id);
    if (server == null) {
      throw CatalogException('not_found', 'MCP server not installed: $id');
    }
    return server;
  }

  Future<McpServer?> _existingForInstall(Map<String, Object?> arguments) async {
    for (final key in ['id', 'key']) {
      final id = _string(arguments[key])?.trim() ?? '';
      if (id.isEmpty) continue;
      final match = await repository.findById(id);
      if (match != null) return match;
    }
    return null;
  }

  static Map<String, Object?> _serverSpecFromArgs(
    Map<String, Object?> args, {
    required bool requireCommand,
  }) {
    final url = _string(args['url'])?.trim();
    final typeArg = _string(args['type'])?.trim().toLowerCase();
    final command = _string(args['command'])?.trim();
    final type =
        typeArg ??
        ((url != null && url.isNotEmpty)
            ? 'http'
            : (requireCommand ? 'stdio' : null));
    final server = <String, Object?>{if (type != null) 'type': type};
    final effectiveType = type ?? 'stdio';
    if (effectiveType == 'http' ||
        effectiveType == 'sse' ||
        effectiveType == 'streamable-http') {
      if (url != null && url.isNotEmpty) server['url'] = url;
    } else {
      if ((command == null || command.isEmpty) && requireCommand) {
        throw CatalogException(
          'invalid_args',
          'create_mcp requires command for stdio',
        );
      }
      if (command != null && command.isNotEmpty) server['command'] = command;
      final cmdArgs = _stringList(args['args']);
      if (cmdArgs != null) server['args'] = cmdArgs;
    }
    _copySecretMap(server, args['env'], 'env');
    _copySecretMap(server, args['headers'], 'headers');
    return server;
  }

  static Map<String, Map<String, Object?>> _serversFromJson(Object decoded) {
    if (decoded is! Map) {
      throw CatalogException('invalid_args', 'MCP JSON must be an object');
    }
    final root = decoded.cast<String, Object?>();
    final wrapped = root['mcpServers'];
    final raw = wrapped is Map ? wrapped : root;
    return {
      for (final entry in raw.entries)
        if (entry.value is Map)
          entry.key.toString(): (entry.value as Map).cast<String, Object?>(),
    };
  }

  static Map<String, Object?> _redactedJson(McpServer server) {
    final json = server.toJson();
    json['server'] = _redactSecrets(server.server);
    return json;
  }

  static Map<String, Object?> _redactSecrets(Map<String, Object?> spec) {
    final out = Map<String, Object?>.from(spec);
    for (final key in const ['env', 'headers']) {
      final raw = out[key];
      if (raw is! Map) continue;
      out[key] = {
        for (final entry in raw.entries)
          entry.key.toString(): entry.value is String ? '***' : entry.value,
      };
    }
    return out;
  }

  static void _copySecretMap(
    Map<String, Object?> server,
    Object? raw,
    String key,
  ) {
    if (raw is! Map) return;
    server[key] = {
      for (final entry in raw.entries) entry.key.toString(): entry.value,
    };
  }

  static String _requireId(CatalogRequest req) {
    final id = _string(req.arguments['id'])?.trim() ?? '';
    if (id.isEmpty) {
      throw CatalogException('invalid_args', 'id is required');
    }
    return id;
  }

  static List<String>? _stringList(Object? value) {
    if (value is! List) return null;
    return [for (final item in value) item.toString()];
  }

  static String? _string(Object? value) => value is String ? value : null;
}
