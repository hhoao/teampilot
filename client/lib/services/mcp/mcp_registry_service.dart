import '../../models/mcp_registry_source.dart';
import '../../models/mcp_server_spec.dart';
import '../../models/team_config.dart';
import '../cli/registry/capabilities/mcp_capability.dart';
import '../cli/registry/cli_tool_registry.dart';
import '../cli/cursor/provider/cursor_workspace_warm_tier.dart';
import '../cli/registry/capabilities/cli_session_capability.dart';
import '../cli/claude/capabilities/mcp_project_cleanup.dart';
import '../storage/runtime_layout.dart';
import '../io/filesystem.dart';
import '../io/local_filesystem.dart';
import '../storage/app_storage.dart';
import '../plugin/installed_plugin_catalog.dart';
import '../resource/assemblers/mcp_assembler.dart';
import '../resource/contribution/resource_origin.dart';
import '../resource/providers/catalog_mcp_contribution_provider.dart';
import '../resource/providers/extra_mcp_contribution_provider.dart';
import '../resource/providers/mcp_contribution_provider.dart';
import '../resource/providers/plugin_mcp_contribution_provider.dart';
import '../resource/providers/smithery_mcp_contribution_provider.dart';
import 'mcp_registry_config_service.dart';

/// Merges team MCP catalog into member CLI native MCP config files.
class McpRegistryService {
  McpRegistryService({
    required this.layout,
    Filesystem? fs,
    McpRegistryConfigService? registryConfigService,
    CliToolRegistry? cliRegistry,
  }) : _fs = fs ?? LocalFilesystem(),
       _registryConfigService =
           registryConfigService ??
           McpRegistryConfigService(
             fs: fs,
             teampilotRoot: layout.teampilotRoot,
           ),
       _cliRegistry = cliRegistry ?? CliToolRegistry.builtIn();

  final RuntimeLayout layout;
  final Filesystem _fs;
  final McpRegistryConfigService _registryConfigService;
  final CliToolRegistry _cliRegistry;
  final McpAssembler _assembler = const McpAssembler();

  Future<void> writeForSession({
    required String workspaceId,
    required String teamId,
    required String sessionId,
    CliTool cli = CliTool.claude,
    String? memberId,
    Map<String, Map<String, Object?>>? extraServers,
    Iterable<String> pluginIds = const [],
    Iterable<String> projectMcpRoots = const [],
  }) async {
    final trimmedWorkspaceId = workspaceId.trim();
    final trimmedTeamId = teamId.trim();
    final trimmedSessionId = sessionId.trim();
    if (trimmedWorkspaceId.isEmpty ||
        trimmedTeamId.isEmpty ||
        trimmedSessionId.isEmpty) {
      return;
    }

    final assembled = await _assemble(
      cli: cli,
      snapshotPath: layout.identityMcpServersFile(trimmedTeamId),
      extraServers: extraServers,
      pluginIds: pluginIds,
    );
    final specs = assembled.result.servers;
    if (specs.isEmpty) return;

    await _writeToTool(
      tool: cli,
      workspaceId: trimmedWorkspaceId,
      sessionId: trimmedSessionId,
      memberId: memberId,
      specs: specs,
    );

    await maybeRemoveStaleProjectTeammateBus(
      fs: _fs,
      extraServers: extraServers,
      projectRoots: projectMcpRoots,
    );

    if (assembled.hasCatalogSource) {
      await _mergeAppCredentials(
        tool: cli,
        workspaceId: trimmedWorkspaceId,
        sessionId: trimmedSessionId,
        memberId: memberId,
      );
    }
  }

  /// Writes team MCP catalog into the cursor workspace warm tier (`mcp.base.json`).
  Future<void> writeCursorWorkspaceMcpBase({
    required String workspaceId,
    required String teamId,
    Map<String, Map<String, Object?>>? extraServers,
    Iterable<String> pluginIds = const [],
    Iterable<String> projectMcpRoots = const [],
  }) async {
    final trimmedWorkspaceId = workspaceId.trim();
    final trimmedTeamId = teamId.trim();
    if (trimmedWorkspaceId.isEmpty || trimmedTeamId.isEmpty) return;

    final assembled = await _assemble(
      cli: CliTool.cursor,
      snapshotPath: layout.identityMcpServersFile(trimmedTeamId),
      extraServers: extraServers,
      pluginIds: pluginIds,
    );
    final specs = assembled.result.servers;
    if (specs.isEmpty) return;

    final writer = _cliRegistry.capability<McpCapability>(CliTool.cursor);
    if (writer == null) return;

    await writer.write(
      fs: _fs,
      configDir: CursorWorkspaceWarmTier.sharedRoot(
        layout,
        trimmedWorkspaceId,
        trimmedTeamId,
      ),
      servers: specs,
      outputBasename: CursorWorkspaceWarmTier.mcpBaseFileName,
    );

    await maybeRemoveStaleProjectTeammateBus(
      fs: _fs,
      extraServers: extraServers,
      projectRoots: projectMcpRoots,
    );
  }

  /// Merges app MCP OAuth credentials into a mixed-mode member cursor config dir.
  Future<void> mergeCursorMemberMcpCredentials({
    required String workspaceId,
    required String sessionId,
    required String teamId,
    required String memberId,
  }) async {
    final trimmedWorkspaceId = workspaceId.trim();
    final trimmedSessionId = sessionId.trim();
    final trimmedTeamId = teamId.trim();
    final trimmedMemberId = memberId.trim();
    if (trimmedWorkspaceId.isEmpty ||
        trimmedSessionId.isEmpty ||
        trimmedTeamId.isEmpty ||
        trimmedMemberId.isEmpty) {
      return;
    }

    final assembled = await _assemble(
      cli: CliTool.cursor,
      snapshotPath: layout.identityMcpServersFile(trimmedTeamId),
    );
    if (!assembled.hasCatalogSource) {
      return;
    }

    final writer = _cliRegistry.capability<McpCapability>(CliTool.cursor);
    if (writer == null) return;

    await writer.mergeAppCredentials(
      fs: _fs,
      appConfigDir: layout.appToolRoot(CliTool.cursor.value),
      sessionConfigDir: _sessionConfigDir(
        tool: CliTool.cursor,
        workspaceId: trimmedWorkspaceId,
        sessionId: trimmedSessionId,
        memberId: trimmedMemberId,
        teamId: trimmedTeamId,
      ),
      fallbackAppConfigDir: layout.appToolRoot(CliTool.claude.value),
    );
  }

  /// Simple mode: resolve MCP specs from catalog ids (no identities-runtime).
  Future<void> writeForSimpleSession({
    required String workspaceId,
    required String sessionId,
    required List<String> mcpServerIds,
    CliTool cli = CliTool.claude,
    Map<String, Map<String, Object?>>? extraServers,
    Iterable<String> pluginIds = const [],
    Iterable<String> projectMcpRoots = const [],
  }) async {
    final trimmedWorkspaceId = workspaceId.trim();
    final trimmedSessionId = sessionId.trim();
    if (trimmedWorkspaceId.isEmpty || trimmedSessionId.isEmpty) {
      return;
    }

    final assembled = await _assemble(
      cli: cli,
      mcpServerIds: mcpServerIds,
      extraServers: extraServers,
      pluginIds: pluginIds,
    );
    final specs = assembled.result.servers;
    if (specs.isEmpty) return;

    await _writeToTool(
      tool: cli,
      workspaceId: trimmedWorkspaceId,
      sessionId: trimmedSessionId,
      specs: specs,
    );

    await maybeRemoveStaleProjectTeammateBus(
      fs: _fs,
      extraServers: extraServers,
      projectRoots: projectMcpRoots,
    );

    if (assembled.hasCatalogSource) {
      await _mergeAppCredentials(
        tool: cli,
        workspaceId: trimmedWorkspaceId,
        sessionId: trimmedSessionId,
      );
    }
  }

  Future<_McpAssembly> _assemble({
    required CliTool cli,
    String? snapshotPath,
    List<String> mcpServerIds = const [],
    Map<String, Map<String, Object?>>? extraServers,
    Iterable<String> pluginIds = const [],
  }) async {
    final hasIds = mcpServerIds.any((id) => id.trim().isNotEmpty);
    final trimmedSnapshot = snapshotPath?.trim() ?? '';
    CatalogMcpContributionProvider? catalogProvider;
    if (trimmedSnapshot.isNotEmpty) {
      catalogProvider =
          await CatalogMcpContributionProvider.fromSnapshotIfPresent(
            snapshotPath: trimmedSnapshot,
            fs: _fs,
            originKind: ResourceOriginKind.team,
          );
    } else if (hasIds) {
      catalogProvider = CatalogMcpContributionProvider(fs: _fs);
    }

    final providers = <McpContributionProvider>[];
    String? smitheryToken;
    if (catalogProvider != null) {
      final registry = await _registryConfigService.load();
      smitheryToken = registry.byKind(McpRegistrySourceKind.smithery)?.apiToken;
      providers.add(
        SmitheryMcpContributionProvider(
          source: catalogProvider,
          apiToken: smitheryToken,
        ),
      );
    }
    if (extraServers?.isNotEmpty == true) {
      providers.add(ExtraMcpContributionProvider());
    }

    final enabledPlugins = pluginIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toList(growable: false);
    if (enabledPlugins.isNotEmpty) {
      providers.add(
        PluginMcpContributionProvider(
          fs: _fs,
          pluginsRoot: AppPaths.pluginsDirForTeampilotRoot(
            layout.teampilotRoot,
          ),
          catalog: await InstalledPluginCatalog.load(_fs, layout.teampilotRoot),
          enabledPluginIds: enabledPlugins,
        ),
      );
    }

    final result = await _assembler.assemble(
      context: McpProviderContext(
        cli: cli,
        mcpServerIds: mcpServerIds,
        extraServerEntries: extraServers ?? const {},
        credentials: {if (smitheryToken != null) 'smithery': smitheryToken},
      ),
      providers: providers,
    );
    return _McpAssembly(
      result: result,
      hasCatalogSource: catalogProvider != null,
    );
  }

  Future<void> _writeToTool({
    required CliTool tool,
    required String workspaceId,
    required String sessionId,
    required List<McpServerSpec> specs,
    String? memberId,
    String? teamId,
  }) async {
    final writer = _cliRegistry.capability<McpCapability>(tool);
    if (writer == null) return;
    final configDir = _sessionConfigDir(
      tool: tool,
      workspaceId: workspaceId,
      sessionId: sessionId,
      memberId: memberId,
      teamId: teamId,
    );
    await writer.write(fs: _fs, configDir: configDir, servers: specs);
  }

  Future<void> _mergeAppCredentials({
    required CliTool tool,
    required String workspaceId,
    required String sessionId,
    String? memberId,
    String? teamId,
  }) async {
    final writer = _cliRegistry.capability<McpCapability>(tool);
    if (writer == null) return;
    await writer.mergeAppCredentials(
      fs: _fs,
      appConfigDir: layout.appToolRoot(tool.value),
      sessionConfigDir: _sessionConfigDir(
        tool: tool,
        workspaceId: workspaceId,
        sessionId: sessionId,
        memberId: memberId,
        teamId: teamId,
      ),
      fallbackAppConfigDir: layout.appToolRoot(CliTool.claude.value),
    );
  }

  String _sessionConfigDir({
    required CliTool tool,
    required String workspaceId,
    required String sessionId,
    String? memberId,
    String? teamId,
  }) {
    return sessionConfigDirForTool(
      tool,
      layout,
      workspaceId: workspaceId,
      sessionId: sessionId,
      memberId: memberId,
      teamId: teamId,
    );
  }
}

final class _McpAssembly {
  const _McpAssembly({required this.result, required this.hasCatalogSource});

  final McpAssemblyResult result;
  final bool hasCatalogSource;
}
