import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:teampilot/theme/app_icon_sizes.dart';

import '../../theme/app_fonts.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/app_provider_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/app_provider_config.dart';
import '../../models/llm_config.dart';
import '../../services/provider/claude/claude_official_provider.dart';
import '../../services/provider/tool_config_generator.dart';
import '../../theme/workspace_surface_layers.dart';
import '../app_icon_button.dart';
import 'claude_official_credential_actions.dart';
import 'cursor_credential_actions.dart';
import 'provider_brand_icon.dart';

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
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              ProviderBrandIcon.fromConfig(provider, size: 40, borderRadius: 10),
              const SizedBox(width: 12),
              Expanded(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      provider.name,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (isOfficialClaudeProvider(provider))
                      ClaudeOfficialCredentialStatusBadge(
                        ready: provider.hasClaudeCredentialsReady,
                      ),
                    if (provider.cli == CliTool.cursor)
                      CursorCredentialStatusBadge(
                        ready: provider.hasCursorCredentialsReady,
                      ),
                  ],
                ),
              ),
              if (provider.cli == CliTool.flashskyai)
                TextButton.icon(
                  onPressed: onShowModels,
                  icon: const Icon(Icons.hub_outlined, size: AppIconSizes.md),
                  label: Text(l10n.providerListModelCount(modelCount)),
                ),
              AppIconButton(
                icon: Icons.edit_outlined,
                tooltip: l10n.editProvider,
                onTap: onEdit,
              ),
              AppIconButton(
                icon: Icons.delete_outline,
                tooltip: l10n.deleteProviderTooltip,
                onTap: onDelete,
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
          const SizedBox(height: 24),
          ClaudeOfficialCredentialActions(provider: provider),
          CursorCredentialActions(provider: provider),
          const SizedBox(height: 24),
          Text(l10n.jsonPreview, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          _ProviderJsonPreview(provider: provider),
        ],
      ),
    );
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
      final json = widget.provider.cli == CliTool.flashskyai
          ? _generator
                .buildFlashskyaiLlmConfig(widget.provider)
                .toMaskedJsonString()
          : const JsonEncoder.withIndent(
              '  ',
            ).convert(_maskedProviderJson(widget.provider));
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
      decoration: workspaceCodeDecoration(cs),
      child: json == null
          ? const SizedBox(
              height: 120,
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            )
          : SelectableText(
              json,
              style: appMonoTextStyle(
                context,
                base: Theme.of(context).textTheme.bodySmall,
              ),
            ),
    );
  }
}

Map<String, Object?> _maskedProviderJson(AppProviderConfig provider) {
  final json = Map<String, Object?>.from(provider.toJson());
  if ((json['apiKey'] as String? ?? '').isNotEmpty) {
    json['apiKey'] = '***';
  }
  return json;
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
            width: 100,
            child: Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
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
