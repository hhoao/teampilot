import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../cubits/app_provider_cubit.dart';
import '../../cubits/llm_config_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/app_provider_config.dart';
import '../../services/app/platform_utils.dart';
import '../../utils/app_keys.dart';
import '../../widgets/app_provider/app_provider_detail_panel.dart';
import '../../widgets/app_provider/app_provider_form_sheet.dart';
import '../../widgets/settings/workspace_hub_shell.dart';
import 'llm_config_helpers.dart';
import 'llm_config_routes.dart';
import 'llm_app_provider_models_panel.dart';
import 'llm_providers_list_content.dart';
import 'llm_providers_tab_content.dart';

export 'llm_config_routes.dart';

class LlmConfigWorkspace extends StatelessWidget {
  const LlmConfigWorkspace({
    this.initialCli,
    this.showAddProviderOnOpen = false,
    this.showHeading = true,
    super.key,
  });

  final CliTool? initialCli;
  final bool showAddProviderOnOpen;
  final bool showHeading;

  @override
  Widget build(BuildContext context) {
    final cli = initialCli;
    if (cli != null &&
        context.read<AppProviderCubit>().state.selectedCli != cli) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) {
          context.read<AppProviderCubit>().setSelectedCli(cli);
        }
      });
    }
    final l10n = context.l10n;
    final controller = context.watch<LlmConfigCubit>();
    final body = useAndroidHubNavigation(context)
        ? LlmProvidersListContent(controller: controller, hubStyle: true)
        : LlmProvidersTabContent(
            controller: controller,
            showAddProviderOnOpen: showAddProviderOnOpen,
          );

    return Column(
      key: AppKeys.llmConfigWorkspace,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showHeading) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: WorkspaceSectionHeading(
              title: l10n.appProviderCatalogLabel,
              subtitle: l10n.appProviderCatalogHint,
            ),
          ),
        ],
        Expanded(child: body),
      ],
    );
  }
}

/// Android: full-screen provider configuration.
class LlmProviderConfigPage extends StatelessWidget {
  const LlmProviderConfigPage({
    required this.cli,
    required this.providerName,
    super.key,
  });

  final CliTool cli;
  final String providerName;

  @override
  Widget build(BuildContext context) {
    final appCubit = context.watch<AppProviderCubit>();
    if (appCubit.state.selectedCli != cli) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) {
          context.read<AppProviderCubit>().setSelectedCli(cli);
        }
      });
    }
    final provider = appCubit.state
        .providersFor(cli)
        .where((p) => p.id == providerName)
        .firstOrNull;

    if (appCubit.state.selectedId != providerName) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        appCubit.selectProvider(providerName);
      });
    }

    return WorkspaceSectionPage(
      pageKey: AppKeys.llmProviderDetail,
      child: provider == null
          ? Center(child: Text('${context.l10n.missingProvider} $providerName'))
          : AppProviderDetailPanel(
              provider: provider,
              onEdit: () =>
                  context.push(llmProviderEditRoute(cli, provider.id)),
              onDelete: () async {
                await confirmDeleteAppProvider(context, provider.id);
                if (context.mounted) {
                  context.go(llmCliRoute(cli));
                }
              },
              onShowModels: () {
                if (provider.cli == CliTool.flashskyai) {
                  context.push(llmProviderModelsRoute(cli, provider.id));
                }
              },
            ),
    );
  }
}

class LlmProviderAddPage extends StatelessWidget {
  const LlmProviderAddPage({required this.cli, super.key});

  final CliTool cli;

  @override
  Widget build(BuildContext context) {
    final appCubit = context.read<AppProviderCubit>();
    if (context.watch<AppProviderCubit>().state.selectedCli != cli) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) {
          context.read<AppProviderCubit>().setSelectedCli(cli);
        }
      });
    }

    return WorkspaceSectionPage(
      pageKey: AppKeys.llmProviderDetail,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: AppProviderFormPage(
          cli: cli,
          onCliChanged: (nextCli) => context.go(llmProviderAddRoute(nextCli)),
          onCancel: () => context.go(llmCliRoute(cli)),
          onSaved: (draft) async {
            final id = await saveNewAppProvider(context, draft);
            if (!context.mounted || id == null) return;
            appCubit.selectProvider(id);
            context.go(llmProviderConfigRoute(draft.cli, id));
          },
        ),
      ),
    );
  }
}

class LlmProviderEditPage extends StatelessWidget {
  const LlmProviderEditPage({
    required this.cli,
    required this.providerName,
    super.key,
  });

  final CliTool cli;
  final String providerName;

  @override
  Widget build(BuildContext context) {
    final appCubit = context.watch<AppProviderCubit>();
    final provider = appCubit.state
        .providersFor(cli)
        .where((p) => p.id == providerName)
        .firstOrNull;

    return WorkspaceSectionPage(
      pageKey: AppKeys.llmProviderDetail,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: provider == null
            ? Center(
                child: Text('${context.l10n.missingProvider} $providerName'),
              )
            : AppProviderFormPage(
                cli: cli,
                existing: provider,
                onCancel: () =>
                    context.go(llmProviderConfigRoute(cli, provider.id)),
                onSaved: (draft) async {
                  await saveExistingAppProvider(
                    context,
                    provider,
                    draft: draft,
                  );
                  if (!context.mounted) return;
                  context.go(llmProviderConfigRoute(cli, provider.id));
                },
              ),
      ),
    );
  }
}

/// Android: models for one provider.
class LlmProviderModelsPage extends StatelessWidget {
  const LlmProviderModelsPage({
    required this.cli,
    required this.providerName,
    super.key,
  });

  final CliTool cli;
  final String providerName;

  @override
  Widget build(BuildContext context) {
    final appCubit = context.watch<AppProviderCubit>();
    final provider = appCubit.state
        .providersFor(cli)
        .where((p) => p.id == providerName)
        .firstOrNull;

    return WorkspaceSectionPage(
      pageKey: AppKeys.llmProviderModels,
      child: provider == null
          ? Center(child: Text('${context.l10n.missingProvider} $providerName'))
          : LlmAppProviderModelsPanel(
              provider: provider,
              onBack: () => context.pop(),
            ),
    );
  }
}
