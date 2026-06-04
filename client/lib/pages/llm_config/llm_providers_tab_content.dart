import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../cubits/app_provider_cubit.dart';
import '../../cubits/llm_config_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/app_provider_config.dart';
import '../../models/layout_preferences.dart';
import '../../services/app/platform_utils.dart';
import '../../widgets/app_provider/app_provider_detail_panel.dart';
import '../../widgets/app_provider/app_provider_form_sheet.dart';
import '../../widgets/split_layout.dart';
import 'llm_config_helpers.dart';
import 'llm_config_routes.dart';
import 'llm_app_provider_models_panel.dart';
import 'llm_providers_list_content.dart';

// --- Providers tab: split view ---

class LlmProvidersTabContent extends StatefulWidget {
  const LlmProvidersTabContent({super.key, 
    required this.controller,
    this.showAddProviderOnOpen = false,
  });

  final LlmConfigCubit controller;
  final bool showAddProviderOnOpen;

  @override
  State<LlmProvidersTabContent> createState() => LlmProvidersTabContentState();
}

class LlmProvidersTabContentState extends State<LlmProvidersTabContent> {
  String? _modelsProviderId;
  String? _editingProviderId;
  late bool _showAddProvider;

  LlmConfigCubit get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _showAddProvider = widget.showAddProviderOnOpen;
  }

  @override
  void didUpdateWidget(covariant LlmProvidersTabContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.showAddProviderOnOpen && widget.showAddProviderOnOpen) {
      setState(() {
        _showAddProvider = true;
        _editingProviderId = null;
        _modelsProviderId = null;
      });
    }
  }

  void _closeRightPanelEditor() {
    setState(() {
      _showAddProvider = false;
      _editingProviderId = null;
    });
  }

  void _openEditProvider(String providerId) {
    setState(() {
      _editingProviderId = providerId;
      _showAddProvider = false;
      _modelsProviderId = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final appCubit = context.watch<AppProviderCubit>();
    final appState = appCubit.state;
    final selected = appState.selectedProvider;

    final showModels =
        _modelsProviderId != null &&
        selected != null &&
        _modelsProviderId == selected.id &&
        selected.cli == AppProviderCli.flashskyai;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: TwoPaneSplitView(
        axis: Axis.horizontal,
        initialFraction: 0.34,
        minSize: 220,
        minSecondarySize: LayoutPreferences.minLlmProviderDetailWidth,
        maxSize: 560,
        first: Padding(
          padding: const EdgeInsets.only(right: 6),
          child: LlmProvidersListContent(
            controller: _controller,
            onSelected: () => setState(() {
              _modelsProviderId = null;
              _showAddProvider = false;
              _editingProviderId = null;
            }),
            onAdd: () => setState(() {
              _modelsProviderId = null;
              _showAddProvider = true;
              _editingProviderId = null;
            }),
            onEdit: (provider) => _openEditProvider(provider.id),
          ),
        ),
        second: Padding(
          padding: const EdgeInsets.only(left: 6),
          child: LlmWorkspaceDetailCard(
            child: _buildRightPanelContent(
              context,
              appState: appState,
              selected: selected,
              showModels: showModels,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRightPanelContent(
    BuildContext context, {
    required AppProviderState appState,
    required AppProviderConfig? selected,
    required bool showModels,
  }) {
    if (_showAddProvider) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: AppProviderFormPage(
          cli: appState.selectedCli,
          onCliChanged: (cli) async {
            await context.read<AppProviderCubit>().setSelectedCli(cli);
            if (!mounted) return;
            setState(() => _modelsProviderId = null);
          },
          onCancel: _closeRightPanelEditor,
          onSaved: (draft) async {
            final id = await saveNewAppProvider(context, draft);
            if (!mounted || id == null) return;
            setState(() {
              _showAddProvider = false;
              _editingProviderId = null;
              _modelsProviderId = null;
            });
          },
        ),
      );
    }

    if (selected != null &&
        _editingProviderId != null &&
        selected.id == _editingProviderId) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: AppProviderFormPage(
          cli: selected.cli,
          existing: selected,
          onCancel: _closeRightPanelEditor,
          onSaved: (draft) async {
            await saveExistingAppProvider(context, selected, draft: draft);
            if (!mounted) return;
            _closeRightPanelEditor();
          },
        ),
      );
    }

    if (selected == null) {
      return Center(child: Text(context.l10n.selectProvider));
    }

    if (showModels) {
      return LlmAppProviderModelsPanel(
        provider: selected,
        onBack: () => setState(() => _modelsProviderId = null),
      );
    }

    return AppProviderDetailPanel(
      provider: selected,
      onEdit: () => _openEditProvider(selected.id),
      onDelete: () => confirmDeleteAppProvider(context, selected.id),
      onShowModels: () {
        if (selected.cli != AppProviderCli.flashskyai) return;
        if (useAndroidHubNavigation(context)) {
          context.push(llmProviderModelsRoute(selected.cli, selected.id));
        } else {
          setState(() => _modelsProviderId = selected.id);
        }
      },
    );
  }
}
