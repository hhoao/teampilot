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
    final cubit = context.read<AppProviderCubit>();
    final llm = cubit.flashskyaiLlmConfigFor(provider);
    final modelCount = llm.models.length;
    final requiresKey = provider.requiresApiKey;

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
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final tool in provider.enabledTools)
                Chip(label: Text(_toolLabel(l10n, tool))),
            ],
          ),
          const SizedBox(height: 24),
          Text(l10n.jsonPreview, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: SelectableText(
              const ToolConfigGenerator()
                  .buildFlashskyaiLlmConfig(provider)
                  .toMaskedJsonString(),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
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
