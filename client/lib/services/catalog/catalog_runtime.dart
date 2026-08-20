import '../../models/app_session.dart';
import '../../models/runtime_target.dart';
import '../../models/workspace_folder.dart';
import '../../repositories/mcp_repository.dart';
import '../../repositories/plugin_repository.dart';
import '../../repositories/session_repository.dart';
import '../../repositories/skill_repository.dart';
import '../../repositories/workspace_project_config_repository.dart';
import '../io/filesystem.dart';
import '../plugin/plugin_install_service.dart';
import '../skill/skill_acquisition_engine.dart';
import '../skill/skill_install_service.dart';
import '../storage/app_storage.dart';
import '../storage/runtime_context_registry.dart';
import '../storage/work_target_canonicalizer.dart';
import 'catalog_kind_registry.dart';
import 'catalog_mcp_handler.dart';
import 'catalog_mutation_bus.dart';
import 'catalog_workspace_binder.dart';
import 'modules/mcp_catalog_module.dart';
import 'modules/plugin_catalog_module.dart';
import 'modules/skill_catalog_module.dart';

/// Assembled catalog MCP graph: modules, registry, handler, mutation bus.
///
/// App shell attaches [handler] to the gateway and subscribes cubits to [bus].
/// Tests call [assemble] without Flutter widgets.
class CatalogRuntime {
  CatalogRuntime({
    required this.bus,
    required this.binder,
    required this.registry,
    required this.handler,
    required this.resolveSession,
  });

  final CatalogMutationBus bus;
  final CatalogWorkspaceBinder binder;
  final CatalogKindRegistry registry;
  final CatalogMcpHandler handler;
  final Future<CatalogMcpSession?> Function(String sessionId) resolveSession;

  static CatalogRuntime assemble({
    SessionRepository? sessions,
    RuntimeContextRegistry? runtimeContexts,
    SkillRepository? skillRepository,
    SkillInstallService? skillInstall,
    SkillAcquisitionEngine? skillEngine,
    PluginRepository? pluginRepository,
    PluginInstallService? pluginInstall,
    McpRepository? mcpRepository,
    WorkspaceProjectConfigRepository? workspaceConfig,
    CatalogMutationBus? bus,
  }) {
    final mutationBus = bus ?? CatalogMutationBus();
    final configRepo = workspaceConfig ?? WorkspaceProjectConfigRepository();
    final binder = CatalogWorkspaceBinder(repo: configRepo);
    final skills = skillRepository ?? SkillRepository();
    final plugins = pluginRepository ?? PluginRepository();
    final mcp = mcpRepository ?? McpRepository();

    final registry = CatalogKindRegistry()
      ..register(
        SkillCatalogModule(
          repository: skills,
          install: skillInstall ?? skills.install,
          binder: binder,
          bus: mutationBus,
          engine: skillEngine,
          workspaceConfig: configRepo,
        ),
      )
      ..register(
        PluginCatalogModule(
          repository: plugins,
          install: pluginInstall ?? plugins.install,
          binder: binder,
          bus: mutationBus,
          workspaceConfig: configRepo,
        ),
      )
      ..register(
        McpCatalogModule(
          repository: mcp,
          binder: binder,
          bus: mutationBus,
          workspaceConfig: configRepo,
        ),
      );

    return CatalogRuntime(
      bus: mutationBus,
      binder: binder,
      registry: registry,
      handler: CatalogMcpHandler(registry: registry),
      resolveSession: (sessionId) => resolveCatalogSession(
        sessionId,
        sessions: sessions,
        runtimeContexts: runtimeContexts,
      ),
    );
  }

  /// `findById` → folder paths as [CatalogMcpSession.allowedRoots].
  ///
  /// Work fs: cached/cheap launch target when available; otherwise
  /// [AppStorage.fs] for local and [RuntimeContextRegistry] for ssh/wsl.
  static Future<CatalogMcpSession?> resolveCatalogSession(
    String sessionId, {
    SessionRepository? sessions,
    RuntimeContextRegistry? runtimeContexts,
  }) async {
    if (sessions == null) return null;
    final session = await sessions.findById(sessionId);
    if (session == null) return null;
    return CatalogMcpSession(
      sessionId: session.sessionId,
      workspaceId: session.workspaceId,
      workFs: await workFsForSession(session, runtimeContexts: runtimeContexts),
      allowedRoots: [
        for (final path in session.folderPaths)
          if (path.isNotEmpty) path,
      ],
    );
  }

  static Future<Filesystem> workFsForSession(
    AppSession session, {
    RuntimeContextRegistry? runtimeContexts,
  }) async {
    if (runtimeContexts == null) return AppStorage.fs;
    final targetId = session.folders.isEmpty
        ? WorkspaceFolder.localTargetId
        : session.folders.first.targetId;
    late final RuntimeTarget home;
    try {
      home = runtimeContexts.home().target;
    } on StateError {
      home = RuntimeTarget.local();
    }
    final target = WorkTargetCanonicalizer.resolve(targetId, home: home);
    if (target.kind == RuntimeKind.local) {
      return AppStorage.fs;
    }
    return (await runtimeContexts.forTarget(target)).fs;
  }
}
