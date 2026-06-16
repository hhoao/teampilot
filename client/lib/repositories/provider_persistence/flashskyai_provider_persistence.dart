import '../../models/app_provider_config.dart';
import '../../models/llm_config.dart';
import '../../services/storage/runtime_layout.dart';
import 'provider_persistence_strategy.dart';

/// Flashskyai: no per-account credential probing; on save, materialize the
/// merged `cli-defaults/flashskyai/llm_config.json`.
final class FlashskyaiProviderPersistence extends ProviderPersistenceStrategy {
  const FlashskyaiProviderPersistence();

  @override
  CliTool get cli => CliTool.flashskyai;

  @override
  Future<void> reconcileSaved(
    ProviderPersistenceContext ctx,
    List<AppProviderConfig> providers,
  ) async {
    final mergedProviders = <String, LlmProviderConfig>{};
    final mergedModels = <String, LlmModelConfig>{};
    final unknownFields = <String, Object?>{};

    for (final provider in providers) {
      final llm = ctx.generator.buildFlashskyaiLlmConfig(provider);
      mergedProviders.addAll(llm.providers);
      mergedModels.addAll(llm.models);
      unknownFields.addAll(llm.unknownFields);
    }

    final config = LlmConfig(
      providers: mergedProviders,
      models: mergedModels,
      unknownFields: unknownFields,
    );

    final configFile = RuntimeLayout(teampilotRoot: ctx.basePath).appFlashskyaiLlmConfigFile;
    await ctx.generator.writeJsonAtomic(configFile, config.toJson(), fs: ctx.fs);
  }
}
