import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/app_provider_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/app_provider_config.dart';
import '../../models/llm_config.dart';
import '../../services/tool_config_generator.dart';

class AppProviderDetailPanel extends StatelessWidget {
  const AppProviderDetailPanel({
    required this.provider,
    required this.onEdit,
    required this.onDelete,
    required this.onShowModels,
    super.key,
  });

  final AppProviderConfig provider;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onShowModels;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final requiresKey = provider.requiresApiKey;
    final modelCount = provider.flashskyaiModelCount;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  provider.name,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
              if (provider.enables(AppProviderTool.flashskyai))
                TextButton.icon(
                  onPressed: onShowModels,
                  icon: const Icon(Icons.hub_outlined, size: 18),
                  label: Text(l10n.providerListModelCount(modelCount)),
                ),
              IconButton(
                tooltip: l10n.editProvider,
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined),
              ),
              IconButton(
                tooltip: l10n.deleteProviderTooltip,
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
          Text(
            provider.id,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          if (provider.websiteUrl.isNotEmpty)
            _InfoRow(
              label: l10n.appProviderWebsite,
              value: provider.websiteUrl,
            ),
          if (provider.notes.isNotEmpty)
            _InfoRow(label: l10n.notes, value: provider.notes),
          if (requiresKey && provider.baseUrl.isNotEmpty)
            _InfoRow(label: l10n.baseUrl, value: provider.baseUrl),
          if (provider.defaultModel.isNotEmpty)
            _InfoRow(label: l10n.defaultModel, value: provider.defaultModel),
          if (provider.enabledTools.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              provider.enabledTools
                  .map((tool) => _toolLabel(l10n, tool))
                  .join(' · '),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 24),
          Text(l10n.jsonPreview, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          _ProviderJsonPreview(provider: provider),
        ],
      ),
    );
  }

  String _toolLabel(dynamic l10n, AppProviderTool tool) {
    return switch (tool) {
      AppProviderTool.flashskyai => l10n.appProviderToolFlashskyai,
      AppProviderTool.codex => l10n.appProviderToolCodex,
      AppProviderTool.claude => l10n.appProviderToolClaude,
    };
  }
}

/// Builds masked JSON off the UI thread so first paint stays fast.
class _ProviderJsonPreview extends StatefulWidget {
  const _ProviderJsonPreview({required this.provider});

  final AppProviderConfig provider;

  @override
  State<_ProviderJsonPreview> createState() => _ProviderJsonPreviewState();
}

class _ProviderJsonPreviewState extends State<_ProviderJsonPreview> {
  static const _generator = ToolConfigGenerator();
  String? _json;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _scheduleLoad();
  }

  @override
  void didUpdateWidget(covariant _ProviderJsonPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.provider.updatedAt != widget.provider.updatedAt ||
        oldWidget.provider.id != widget.provider.id) {
      _scheduleLoad();
    }
  }

  void _scheduleLoad() {
    final generation = ++_loadGeneration;
    setState(() => _json = null);
    Future<void>.microtask(() {
      if (!mounted || generation != _loadGeneration) return;
      final json = _generator
          .buildFlashskyaiLlmConfig(widget.provider)
          .toMaskedJsonString();
      if (!mounted || generation != _loadGeneration) return;
      setState(() => _json = json);
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final json = _json;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(8),
      ),
      child: json == null
          ? const SizedBox(
              height: 120,
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            )
          : SelectableText(
              json,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(label, style: Theme.of(context).textTheme.labelMedium),
          ),
          Expanded(child: SelectableText(value)),
        ],
      ),
    );
  }
}

/// Bridges FlashskyAI models UI to [AppProviderCubit].
class AppProviderModelsBridge extends StatelessWidget {
  const AppProviderModelsBridge({
    required this.provider,
    required this.child,
    super.key,
  });

  final AppProviderConfig provider;
  final Widget Function(
    BuildContext context,
    LlmConfig config,
    Future<void> Function(Map<String, LlmModelConfig> models) onSave,
  )
  child;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<AppProviderCubit>();
    final config = cubit.flashskyaiLlmConfigFor(provider);
    return child(
      context,
      config,
      (models) => cubit.updateFlashskyaiModels(provider.id, models),
    );
  }
}
