import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/session_preferences_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/app_provider_config.dart';
import '../../services/cli/registry/capabilities/provider_model_capability.dart';
import '../../services/cli/registry/cli_tool_registry_scope.dart';
import '../dropdown/app_dropdown_decoration.dart';
import '../dropdown/app_dropdown_field.dart';
import '../dropdown/app_dropdown_with_custom_input.dart';

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
  final AppDropdownDecoration? decoration;
  final String? hintText;

  @override
  State<ProviderModelPickerField> createState() => _ProviderModelPickerFieldState();
}

class _ProviderModelPickerFieldState extends State<ProviderModelPickerField> {
  RefreshableProviderModelCapability? _refreshableCapability;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _attachCatalogRefresh());
  }

  @override
  void didUpdateWidget(ProviderModelPickerField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cli != widget.cli ||
        oldWidget.providerId != widget.providerId) {
      _detachCatalogRefresh();
      WidgetsBinding.instance.addPostFrameCallback((_) => _attachCatalogRefresh());
    }
  }

  @override
  void dispose() {
    _detachCatalogRefresh();
    super.dispose();
  }

  void _attachCatalogRefresh() {
    if (!mounted) return;
    final capability = CliToolRegistryScope.of(
      context,
    ).capability<ProviderModelCapability>(widget.cli);
    if (capability is! RefreshableProviderModelCapability) return;

    _refreshableCapability = capability;
    capability.catalogUpdates.addListener(_onCatalogUpdated);
    final executable = context.read<SessionPreferencesCubit>().resolveExecutable(
      widget.cli,
    );
    capability.refreshModelCatalog(
      providerId: widget.providerId,
      executable: executable,
    );
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
    ).capability<ProviderModelCapability>(widget.cli);
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
    final deco = widget.decoration ?? AppDropdownDecorations.themed(context);
    final hint = widget.hintText ?? context.l10n.selectModel;
    final isLoading =
        capability is RefreshableProviderModelCapability && candidates.isEmpty;

    Widget picker = switch (mode) {
      ProviderModelPickerMode.catalogDropdown => AppDropdownField<String>(
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
      ProviderModelPickerMode.catalogWithCustomEntry => AppDropdownWithCustomInput(
        key: ValueKey('provider-model-custom-${widget.providerId}'),
        value: widget.value,
        items: candidates,
        hintText: hint,
        decoration: deco,
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
