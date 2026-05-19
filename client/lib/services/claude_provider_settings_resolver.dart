import '../models/app_provider_config.dart';
import '../repositories/app_provider_repository.dart';
import 'tool_config_generator.dart';

/// Resolves Claude Code settings from [providers/providers.json] (in memory).
class ClaudeProviderSettingsResolver {
  ClaudeProviderSettingsResolver({
    required String basePath,
    AppProviderRepository? repository,
    ToolConfigGenerator? generator,
  }) : _repository =
           repository ??
           AppProviderRepository(
             providersFile: AppProviderRepository.providersFileForBasePath(
               basePath,
             ),
           ),
       _generator = generator ?? const ToolConfigGenerator();

  final AppProviderRepository _repository;
  final ToolConfigGenerator _generator;

  Future<Map<String, Object?>?> resolve(String? providerId) async {
    final trimmed = providerId?.trim() ?? '';
    if (trimmed.isEmpty) return null;

    final provider = await _repository.findById(trimmed);
    if (provider == null || !provider.enables(AppProviderTool.claude)) {
      return null;
    }
    return _generator.buildClaudeSettings(provider);
  }
}
