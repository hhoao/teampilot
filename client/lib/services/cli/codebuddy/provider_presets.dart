import '../../../models/app_provider_config.dart';

/// Built-in CodeBuddy provider templates.
///
/// The official row uses the CLI's own machine login (no API key).
/// Custom rows target an OpenAI-compatible `/chat/completions` endpoint, which
/// is the only protocol `models.json` supports.
abstract final class CodebuddyProviderPresets {
  const CodebuddyProviderPresets._();

  static const all = <AppProviderPreset>[
    AppProviderPreset(
      id: 'codebuddy',
      label: 'CodeBuddy',
      template: AppProviderConfig(
        id: 'codebuddy',
        cli: CliTool.codebuddy,
        name: 'CodeBuddy',
        websiteUrl: 'https://www.codebuddy.ai',
        category: AppProviderCategory.official,
        isOfficial: true,
        apiKeyField: 'api_key',
        defaultModel: 'hy3',
        icon: 'codebuddy',
        notes:
            'Isolated login: Sign in opens a CodeBuddy login terminal that '
            'does not touch your global CLI account.',
      ),
    ),
    AppProviderPreset(
      id: 'openai-compatible',
      label: 'OpenAI-compatible',
      template: AppProviderConfig(
        id: 'openai-compatible',
        cli: CliTool.codebuddy,
        name: 'OpenAI-compatible',
        category: AppProviderCategory.custom,
        apiKeyField: 'api_key',
        baseUrl: 'https://api.openai.com/v1',
        defaultModel: 'gpt-5',
      ),
    ),
  ];
}
