import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/session_preferences_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/app_provider_config.dart';
import '../../services/cli/registry/capabilities/provider_capability.dart';
import '../../services/cli/registry/cli_tool_registry_scope.dart';
import 'package:shared_ui/shared_ui.dart';

/// Whether a provider change can affect the live model catalog.
@visibleForTesting
bool providerModelPickerProviderChanged(
  AppProviderConfig? previous,
  AppProviderConfig? current,
) {
  if (identical(previous, current)) return false;
  if (previous == null || current == null) return true;
  return previous.id != current.id ||
      previous.cli != current.cli ||
      previous.apiKey != current.apiKey ||
      previous.apiKeyField != current.apiKeyField ||
      previous.baseUrl != current.baseUrl;
}

/// Registry-driven model picker for team members and workspace CLI defaults.
class ProviderModelPickerField extends StatefulWidget {
  const ProviderModelPickerField({
    required this.cli,
    required this.providerId,
    required this.provider,
    required this.value,
    required this.onChanged,
    this.decoration,
    this.hintText,
    super.key,
  });

  final CliTool cli;
  final String providerId;
  final AppProviderConfig? provider;
  final String value;
  final ValueChanged<String> onChanged;
  final TpSelectDecoration? decoration;
  final String? hintText;

  @override
  State<ProviderModelPickerField> createState() =>
      _ProviderModelPickerFieldState();
}

class _ProviderModelPickerFieldState extends State<ProviderModelPickerField> {
  RefreshableProviderModelCapability? _refreshableCapability;
  bool _catalogLoading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _attachCatalogRefresh(),
    );
  }

  @override
  void didUpdateWidget(ProviderModelPickerField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cli != widget.cli ||
        oldWidget.providerId != widget.providerId ||
        providerModelPickerProviderChanged(
          oldWidget.provider,
          widget.provider,
        )) {
      _detachCatalogRefresh();
      final forceRefresh = providerModelPickerProviderChanged(
        oldWidget.provider,
        widget.provider,
      );
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _attachCatalogRefresh(forceRefresh: forceRefresh),
      );
    }
  }

  @override
  void dispose() {
    _detachCatalogRefresh();
    super.dispose();
  }

  void _attachCatalogRefresh({bool forceRefresh = false}) {
    if (!mounted) return;
    final capability = CliToolRegistryScope.of(
      context,
    ).capability<ProviderCapability>(widget.cli);
    if (capability is! RefreshableProviderModelCapability) return;

    _refreshableCapability = capability;
    capability.catalogUpdates.addListener(_onCatalogUpdated);
    SessionPreferencesCubit? prefs;
    try {
      prefs = context.read<SessionPreferencesCubit>();
    } on ProviderNotFoundException {
      prefs = null;
    }
    setState(() => _catalogLoading = true);
    capability
        .refreshModelCatalog(
          providerId: widget.providerId,
          provider: widget.provider,
          executable: prefs?.resolveExecutable(widget.cli),
          forceRefresh: forceRefresh,
        )
        .whenComplete(() {
          if (mounted) setState(() => _catalogLoading = false);
        });
  }

  void _detachCatalogRefresh() {
    _refreshableCapability?.catalogUpdates.removeListener(_onCatalogUpdated);
    _refreshableCapability = null;
  }

  void _onCatalogUpdated() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final capability = CliToolRegistryScope.of(
      context,
    ).capability<ProviderCapability>(widget.cli);
    if (capability == null || widget.provider == null) {
      return const SizedBox.shrink();
    }

    final mode = capability.pickerMode(widget.provider!);
    if (mode == ProviderModelPickerMode.hidden) {
      return const SizedBox.shrink();
    }

    final candidates = capability.modelCandidates(
      provider: widget.provider,
      providerId: widget.providerId,
      currentModel: widget.value,
    );
    final deco = widget.decoration ?? TpSelectDecorations.themed(context);
    final hint = widget.hintText ?? context.l10n.selectModel;
    final isLoading = _catalogLoading && candidates.isEmpty;

    Widget picker = switch (mode) {
      ProviderModelPickerMode.catalogDropdown => TpSelect<String>(
        key: ValueKey(
          'provider-model-dd-${widget.providerId}-${candidates.join("|")}-${widget.value}',
        ),
        items: candidates,
        initialItem: widget.value.trim().isEmpty ? null : widget.value.trim(),
        hintText: hint,
        decoration: deco,
        onChanged: (next) => widget.onChanged(next ?? ''),
        itemLabel: (item) => item,
      ),
      ProviderModelPickerMode.catalogWithCustomEntry =>
        TpSelectWithCustomInput(
          key: ValueKey('provider-model-custom-${widget.providerId}'),
          value: widget.value,
          items: candidates,
          hintText: hint,
          decoration: deco,
          searchable: true,
          searchMinItems: 8,
          onChanged: widget.onChanged,
        ),
      ProviderModelPickerMode.hidden => const SizedBox.shrink(),
    };

    if (isLoading) {
      picker = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          picker,
          const SizedBox(height: 6),
          LinearProgressIndicator(
            minHeight: 2,
            borderRadius: BorderRadius.circular(1),
          ),
        ],
      );
    }

    return picker;
  }
}
