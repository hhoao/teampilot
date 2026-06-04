import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/app_provider_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/app_provider_config.dart';
import '../../models/llm_config.dart';
import 'llm_provider_models_view.dart';

class LlmAppProviderModelsPanel extends StatelessWidget {
  const LlmAppProviderModelsPanel({
    super.key,
    required this.provider,
    required this.onBack,
  });

  final AppProviderConfig provider;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final appCubit = context.watch<AppProviderCubit>();
    final config = appCubit.flashskyaiLlmConfigFor(provider);
    final llmProvider = config.providers[provider.id];
    if (llmProvider == null) {
      return Center(
        child: Text('${context.l10n.missingProvider} ${provider.id}'),
      );
    }

    Future<void> persist(Map<String, LlmModelConfig> models) {
      return appCubit.updateFlashskyaiModels(provider.id, models);
    }

    return LlmProviderModelsView(
      key: ValueKey('app-models-${provider.id}-${config.models.length}'),
      config: config,
      provider: llmProvider,
      onPersistModels: persist,
      onBack: onBack,
    );
  }
}
