import 'package:flutter/material.dart';

import '../../l10n/l10n_extensions.dart';
import '../../models/mcp_registry_source.dart';
import '../../services/mcp/mcp_registry_browse_service.dart';
import '../../services/mcp/mcp_registry_config_service.dart';
import '../../services/mcp/smithery_mcp_service.dart';
import '../../theme/workspace_surface_layers.dart';
import 'mcp_shared_widgets.dart';

/// Registry API sources (skills repos layout).
class McpRegistriesSection extends StatefulWidget {
  const McpRegistriesSection({super.key});

  @override
  State<McpRegistriesSection> createState() => _McpRegistriesSectionState();
}

class _McpRegistriesSectionState extends State<McpRegistriesSection> {
  final _configService = McpRegistryConfigService();
  final _smithery = SmitheryMcpService();
  final _registry = McpRegistryBrowseService();

  McpRegistrySourcesConfig? _config;
  bool _loading = true;
  String? _testingKind;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _smithery.close();
    _registry.close();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final config = await _configService.load();
    if (!mounted) return;
    setState(() {
      _config = config;
      _loading = false;
    });
  }

  Future<void> _persist(McpRegistrySourcesConfig config) async {
    await _configService.save(config);
    if (!mounted) return;
    setState(() => _config = config);
  }

  String _sourceLabel(McpRegistrySourceKind kind, dynamic l10n) =>
      switch (kind) {
        McpRegistrySourceKind.smithery => l10n.mcpRegistrySmithery,
        McpRegistrySourceKind.officialRegistry => l10n.mcpRegistryOfficial,
      };

  String _registryRowSubtitle(McpRegistrySourceConfig source, dynamic l10n) {
    final name = _sourceLabel(source.kind, l10n);
    if (source.kind == McpRegistrySourceKind.smithery && source.hasApiToken) {
      return '@$name · ${l10n.mcpSmitheryApiTokenSet}';
    }
    return '@$name';
  }

  Future<void> _toggleEnabled(McpRegistrySourceConfig source, bool enabled) async {
    final config = _config;
    if (config == null) return;
    final next = McpRegistrySourcesConfig(
      sources: config.sources
          .map((s) => s.kind == source.kind ? s.copyWith(enabled: enabled) : s)
          .toList(),
    );
    await _persist(next);
  }

  Future<void> _resetSource(McpRegistrySourceConfig source) async {
    final l10n = context.l10n;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.mcpRegistryResetTitle),
        content: Text(l10n.mcpRegistryResetConfirm(_sourceLabel(source.kind, l10n))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.confirm),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    final config = _config;
    if (config == null) return;
    final next = McpRegistrySourcesConfig(
      sources: config.sources
          .map(
            (s) => s.kind == source.kind
                ? s.copyWith(
                    baseUrl: McpRegistrySourceConfig.defaultBaseUrl(source.kind),
                    enabled: true,
                    clearApiToken: true,
                  )
                : s,
          )
          .toList(),
    );
    await _persist(next);
  }

  Future<void> _editSource(McpRegistrySourceConfig source) async {
    final l10n = context.l10n;
    final isSmithery = source.kind == McpRegistrySourceKind.smithery;
    final result = await showDialog<({String baseUrl, String apiToken})>(
      context: context,
      builder: (ctx) => _RegistrySourceEditDialog(
        source: source,
        smithery: _smithery,
        registry: _registry,
      ),
    );
    if (result == null || !mounted) return;
    final editedUrl = result.baseUrl;
    final editedToken = result.apiToken;
    if (editedUrl.isEmpty) return;

    final config = _config;
    if (config == null) return;
    final next = McpRegistrySourcesConfig(
      sources: config.sources
          .map(
            (s) => s.kind == source.kind
                ? s.copyWith(
                    baseUrl: editedUrl,
                    apiToken: isSmithery
                        ? (editedToken.isEmpty ? null : editedToken)
                        : null,
                    clearApiToken: isSmithery && editedToken.isEmpty,
                  )
                : s,
          )
          .toList(),
    );
    await _persist(next);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.mcpRepoConfigSaved)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (_loading || _config == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final sources = _config!.sources;

    return SingleChildScrollView(
      child: McpWorkspaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            McpCardHeader(title: l10n.mcpNavRegistries),
            const SizedBox(height: 12),
            for (final source in sources)
              _RegistryRow(
                source: source,
                label: _registryRowSubtitle(source, l10n),
                testing: _testingKind == source.kind.wireValue,
                onToggle: (v) => _toggleEnabled(source, v),
                onEdit: () => _editSource(source),
                onReset: () => _resetSource(source),
              ),
          ],
        ),
      ),
    );
  }
}

class _RegistrySourceEditDialog extends StatefulWidget {
  const _RegistrySourceEditDialog({
    required this.source,
    required this.smithery,
    required this.registry,
  });

  final McpRegistrySourceConfig source;
  final SmitheryMcpService smithery;
  final McpRegistryBrowseService registry;

  @override
  State<_RegistrySourceEditDialog> createState() =>
      _RegistrySourceEditDialogState();
}

class _RegistrySourceEditDialogState extends State<_RegistrySourceEditDialog> {
  late final TextEditingController _urlCtrl;
  late final TextEditingController _tokenCtrl;
  bool _testing = false;

  bool get _isSmithery =>
      widget.source.kind == McpRegistrySourceKind.smithery;

  @override
  void initState() {
    super.initState();
    _urlCtrl = TextEditingController(text: widget.source.baseUrl);
    _tokenCtrl = TextEditingController(text: widget.source.apiToken ?? '');
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    _tokenCtrl.dispose();
    super.dispose();
  }

  Future<void> _testConnection() async {
    final l10n = context.l10n;
    final url = _urlCtrl.text.trim();
    if (url.isEmpty) return;
    final token = _tokenCtrl.text.trim();
    setState(() => _testing = true);
    try {
      if (_isSmithery) {
        await widget.smithery.fetchServerDetail(
          'github',
          baseUrl: url,
          apiToken: token.isEmpty ? null : token,
        );
      } else {
        await widget.registry.search('', baseUrl: url, pageSize: 1);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.mcpRepoTestOk)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.mcpRepoTestFailed(e.toString()))),
      );
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  void _save() {
    final url = _urlCtrl.text.trim();
    if (url.isEmpty) return;
    Navigator.pop(
      context,
      (baseUrl: url, apiToken: _tokenCtrl.text.trim()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.mcpRegistryEditTitle),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _urlCtrl,
                decoration: InputDecoration(
                  labelText: l10n.mcpRepoApiUrlLabel,
                  hintText: McpRegistrySourceConfig.defaultBaseUrl(
                    widget.source.kind,
                  ),
                ),
                autofocus: !_isSmithery,
              ),
              if (_isSmithery) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _tokenCtrl,
                  obscureText: true,
                  autocorrect: false,
                  decoration: InputDecoration(
                    labelText: l10n.mcpSmitheryApiTokenLabel,
                    hintText: l10n.mcpSmitheryApiTokenHint,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        TextButton(
          onPressed: _testing ? null : _testConnection,
          child: _testing
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(l10n.mcpRepoTestConnection),
        ),
        FilledButton(
          onPressed: _save,
          child: Text(l10n.save),
        ),
      ],
    );
  }
}

class _RegistryRow extends StatelessWidget {
  const _RegistryRow({
    required this.source,
    required this.label,
    required this.testing,
    required this.onToggle,
    required this.onEdit,
    required this.onReset,
  });

  final McpRegistrySourceConfig source;
  final String label;
  final bool testing;
  final ValueChanged<bool> onToggle;
  final VoidCallback onEdit;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textBase = isDark ? Colors.white : const Color(0xFF111827);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onEdit,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: workspaceInsetDecoration(cs, radius: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        source.baseUrl,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: textBase,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '@$label',
                        style: TextStyle(
                          fontSize: 11,
                          color: textBase.withValues(alpha: 0.55),
                        ),
                      ),
                    ],
                  ),
                ),
                if (testing) ...[
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 8),
                ],
                Switch(value: source.enabled, onChanged: onToggle),
                IconButton(
                  tooltip: l10n.mcpRegistryResetTitle,
                  onPressed: onReset,
                  icon: Icon(
                    Icons.delete_outline,
                    size: 18,
                    color: cs.error,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
