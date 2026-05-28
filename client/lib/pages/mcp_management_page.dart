import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../cubits/mcp_cubit.dart';
import '../l10n/l10n_extensions.dart';
import '../theme/workspace_surface_layers.dart';
import '../models/mcp_catalog_listing.dart';
import '../models/mcp_server.dart';
import '../services/app/platform_utils.dart';
import '../models/mcp_registry_source.dart';
import '../services/mcp/mcp_catalog_mapper.dart';
import '../services/mcp/mcp_registry_config_service.dart';
import '../services/mcp/smithery_mcp_auth.dart';
import '../services/mcp/smithery_mcp_service.dart';
import '../utils/app_keys.dart';
import '../utils/debounce/debounce.dart';
import '../widgets/settings/workspace_hub_shell.dart';
import 'mcp/mcp_discovery_section.dart';
import 'mcp/mcp_installed_section.dart';
import 'mcp/mcp_registries_section.dart';
import 'mcp/mcp_routes.dart';

enum McpSection { installed, discovery, registries }

extension McpSectionRoute on McpSection {
  String routeSegment() => name;

  String routePath() => '/mcp/${routeSegment()}';

  String title(AppLocalizations l10n) => switch (this) {
    McpSection.installed => l10n.mcpNavInstalled,
    McpSection.discovery => l10n.mcpNavDiscovery,
    McpSection.registries => l10n.mcpNavRegistries,
  };
}

IconData mcpSectionIcon(McpSection section) => switch (section) {
  McpSection.installed => Icons.dns_outlined,
  McpSection.discovery => Icons.travel_explore_outlined,
  McpSection.registries => Icons.source_outlined,
};

void navigateMcpAdd(BuildContext context) {
  if (useAndroidHubNavigation(context)) {
    context.push(mcpAddRoute());
  } else {
    context.go(mcpAddRoute());
  }
}

void navigateMcpEdit(BuildContext context, McpServer server) {
  final route = mcpEditRoute(server.id);
  if (useAndroidHubNavigation(context)) {
    context.push(route);
  } else {
    context.go(route);
  }
}

void navigateMcpSection(BuildContext context, McpSection target) {
  if (useAndroidHubNavigation(context)) {
    context.push(target.routePath());
  } else {
    context.go(target.routePath());
  }
}

/// Desktop MCP shell: title bar + section nav + body.
class McpWorkspaceShell extends StatelessWidget {
  const McpWorkspaceShell({
    required this.section,
    required this.body,
    required this.onSelectSection,
    this.bodyAnimationKey,
    super.key,
  });

  final McpSection section;
  final Widget body;
  final ValueChanged<McpSection> onSelectSection;
  final Key? bodyAnimationKey;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;

    return Container(
      color: cs.workspacePage,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          WorkspaceHubTitleBar(
            title: l10n.mcpNavTitle,
            subtitle: l10n.mcpSubtitle,
          ),
          Expanded(
            child: WorkspaceSplitShell(
              bodyAnimationKey: bodyAnimationKey,
              nav: McpNavPanel(
                section: section,
                l10n: l10n,
                onSelect: onSelectSection,
              ),
              body: body,
            ),
          ),
        ],
      ),
    );
  }
}

class McpNavPanel extends StatelessWidget {
  const McpNavPanel({
    required this.section,
    required this.l10n,
    required this.onSelect,
    super.key,
  });

  final McpSection section;
  final AppLocalizations l10n;
  final ValueChanged<McpSection> onSelect;

  @override
  Widget build(BuildContext context) {
    return WorkspaceHubNavList(
      sidebarStyle: true,
      entries: [
        for (final value in McpSection.values)
          WorkspaceHubEntry(
            title: value.title(l10n),
            icon: mcpSectionIcon(value),
            selected: section == value,
            onTap: throttledTap(
              'mcp_nav_${value.name}',
              () => onSelect(value),
            ),
          ),
      ],
    );
  }
}

class McpManagementHubPage extends StatelessWidget {
  const McpManagementHubPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return WorkspaceHubPage(
      pageKey: AppKeys.mcpHub,
      title: l10n.mcpNavTitle,
      subtitle: l10n.mcpSubtitle,
      entries: [
        for (final section in McpSection.values)
          WorkspaceHubEntry(
            title: section.title(l10n),
            icon: mcpSectionIcon(section),
            onTap: throttledTap(
              'mcp_hub_${section.name}',
              () => context.push(section.routePath()),
            ),
          ),
      ],
    );
  }
}

class McpManagementPage extends StatefulWidget {
  const McpManagementPage({required this.section, super.key});

  final McpSection section;

  @override
  State<McpManagementPage> createState() => _McpManagementPageState();
}

class _McpManagementPageState extends State<McpManagementPage> {
  @override
  void initState() {
    super.initState();
    context.read<McpCubit>().loadAll();
  }

  Future<McpCatalogListing> _resolveSmitheryListing(
    McpCatalogListing listing,
  ) async {
    final qn = listing.smitheryQualifiedName;
    if (qn == null || qn.isEmpty) return listing;
    try {
      final config = await McpRegistryConfigService().load();
      final baseUrl =
          config.byKind(McpRegistrySourceKind.smithery)?.baseUrl ??
          McpRegistrySourceConfig.defaultBaseUrl(McpRegistrySourceKind.smithery);
      final smithery = config.byKind(McpRegistrySourceKind.smithery);
      final detail = await SmitheryMcpService().fetchServerDetail(
        qn,
        baseUrl: baseUrl,
        apiToken: smithery?.apiToken,
      );
      if (detail != null) {
        return McpCatalogMapper.applySmitheryDetail(listing, detail);
      }
    } catch (_) {
      // Keep gateway URL from list row.
    }
    return listing;
  }

  Future<void> _addFromListing(McpCatalogListing listing) async {
    final cubit = context.read<McpCubit>();
    final existing = cubit.state.servers.where((s) => s.id == listing.id).toList();
    if (existing.isNotEmpty) {
      navigateMcpEdit(context, existing.first);
      return;
    }
    final resolved = listing.source == McpCatalogSource.smithery
        ? await _resolveSmitheryListing(listing)
        : listing;
    if (!mounted) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    var draft = McpCatalogMapper.draftFromListing(resolved, now: now);
    if (resolved.source == McpCatalogSource.smithery) {
      final config = await McpRegistryConfigService().load();
      final token = config.byKind(McpRegistrySourceKind.smithery)?.apiToken;
      draft = draft.copyWith(
        server: SmitheryMcpAuth.applyCatalogBearer(draft.server, token),
      );
    }
    final ok = await cubit.upsert(draft);
    if (!mounted) return;
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.mcpCatalogAdded)),
      );
      return;
    }
    final message = cubit.state.errorMessage;
    if (message != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      navigateMcpEdit(context, draft);
    }
  }

  Future<void> _importFromMachine() async {
    final cubit = context.read<McpCubit>();
    final l10n = context.l10n;
    final preview = await cubit.previewImport();
    if (!mounted) return;
    if (preview.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.mcpImportEmpty)),
      );
      return;
    }

    final overwrite = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.mcpImportExisting),
        content: Text(
          l10n.mcpImportSummary(
            preview.newServers.length,
            preview.conflicts.length,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.cancel),
          ),
          if (preview.conflicts.isNotEmpty)
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l10n.mcpImportOverwrite),
            ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.confirm),
          ),
        ],
      ),
    );
    if (!mounted) return;
    final ok = await cubit.applyImport(
      preview,
      overwriteConflicts: overwrite == true,
    );
    if (!mounted || !ok) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.mcpImportDone)),
    );
  }

  Future<void> _confirmDelete(McpServer server) async {
    final l10n = context.l10n;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.mcpDeleteConfirm),
        content: Text(server.name),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      await context.read<McpCubit>().delete(server.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<McpCubit, McpState>(
      listenWhen: (a, b) =>
          a.errorMessage != b.errorMessage && b.errorMessage != null,
      listener: (context, state) {
        if (state.errorMessage == null) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(state.errorMessage!)),
        );
        context.read<McpCubit>().clearError();
      },
      builder: (context, state) {
        final body = switch (widget.section) {
          McpSection.installed => McpInstalledSection(
            state: state,
            onImport: _importFromMachine,
            onAdd: () => navigateMcpAdd(context),
            onEdit: (s) => navigateMcpEdit(context, s),
            onDelete: _confirmDelete,
            onGoDiscovery: () => navigateMcpSection(
              context,
              McpSection.discovery,
            ),
            onOAuthConnected: () {},
          ),
          McpSection.discovery => McpDiscoverySection(
            onAddListing: _addFromListing,
            onGoRegistries: () => navigateMcpSection(
              context,
              McpSection.registries,
            ),
          ),
          McpSection.registries => const McpRegistriesSection(),
        };

        if (useAndroidHubNavigation(context)) {
          return WorkspaceSectionPage(
            pageKey: AppKeys.mcpWorkspace,
            child: body,
          );
        }

        return McpWorkspaceShell(
          section: widget.section,
          bodyAnimationKey: ValueKey('mcp-body-${widget.section.name}'),
          onSelectSection: (target) => navigateMcpSection(context, target),
          body: body,
        );
      },
    );
  }
}
