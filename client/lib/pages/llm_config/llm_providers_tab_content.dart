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
import '../../widgets/deferred_mount_shell.dart';
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
            child: _LlmProvidersRightPanel(
              showAddProvider: _showAddProvider,
              editingProviderId: _editingProviderId,
              modelsProviderId: _modelsProviderId,
              onCloseEditor: _closeRightPanelEditor,
              onAddSaved: () => setState(() {
                _showAddProvider = false;
                _editingProviderId = null;
                _modelsProviderId = null;
              }),
              onOpenEdit: _openEditProvider,
              onModelsBack: () => setState(() => _modelsProviderId = null),
              onShowModels: (selected) {
                if (selected.cli != CliTool.flashskyai) return;
                if (useAndroidHubNavigation(context)) {
                  context.push(llmProviderModelsRoute(selected.cli, selected.id));
                } else {
                  setState(() => _modelsProviderId = selected.id);
                }
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _LlmProvidersRightPanel extends StatelessWidget {
  const _LlmProvidersRightPanel({
    required this.showAddProvider,
    required this.editingProviderId,
    required this.modelsProviderId,
    required this.onCloseEditor,
    required this.onAddSaved,
    required this.onOpenEdit,
    required this.onModelsBack,
    required this.onShowModels,
  });

  final bool showAddProvider;
  final String? editingProviderId;
  final String? modelsProviderId;
  final VoidCallback onCloseEditor;
  final VoidCallback onAddSaved;
  final ValueChanged<String> onOpenEdit;
  final VoidCallback onModelsBack;
  final ValueChanged<AppProviderConfig> onShowModels;

  @override
  Widget build(BuildContext context) {
    if (showAddProvider) {
      return BlocSelector<AppProviderCubit, AppProviderState, CliTool>(
        selector: (state) => state.selectedCli,
        builder: (context, selectedCli) {
          return Padding(
            padding: const EdgeInsets.all(12),
            child: AppProviderFormPage(
              key: ValueKey(selectedCli),
              cli: selectedCli,
              onCliChanged: (cli) async {
                await context.read<AppProviderCubit>().setSelectedCli(cli);
              },
              onCancel: onCloseEditor,
              onSaved: (draft) async {
                final id = await saveNewAppProvider(context, draft);
                if (!context.mounted || id == null) return;
                onAddSaved();
              },
            ),
          );
        },
      );
    }

    return BlocSelector<AppProviderCubit, AppProviderState, AppProviderConfig?>(
      selector: (state) => state.selectedProvider,
      builder: (context, selected) {
        if (selected != null &&
            editingProviderId != null &&
            selected.id == editingProviderId) {
          return Padding(
            padding: const EdgeInsets.all(12),
            child: AppProviderFormPage(
              cli: selected.cli,
              existing: selected,
              onCancel: onCloseEditor,
              onSaved: (draft) async {
                await saveExistingAppProvider(context, selected, draft: draft);
                if (!context.mounted) return;
                onCloseEditor();
              },
            ),
          );
        }

        if (selected == null) {
          return Center(child: Text(context.l10n.selectProvider));
        }

        final showModels =
            modelsProviderId != null &&
            modelsProviderId == selected.id &&
            selected.cli == CliTool.flashskyai;

        if (showModels) {
          return LlmAppProviderModelsPanel(
            provider: selected,
            onBack: onModelsBack,
          );
        }

        return RepaintBoundary(
          child: DeferredMountShell(
            key: ValueKey('provider-detail-${selected.id}'),
            delayFrames: 1,
            child: AppProviderDetailPanel(
              provider: selected,
              onEdit: () => onOpenEdit(selected.id),
              onDelete: () => confirmDeleteAppProvider(context, selected.id),
              onShowModels: () => onShowModels(selected),
            ),
          ),
        );
      },
    );
  }
}
