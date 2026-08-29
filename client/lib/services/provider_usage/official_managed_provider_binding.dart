import '../../cubits/app_provider_cubit.dart';
import '../../models/app_provider_config.dart';
import '../cli/claude/provider_presets.dart';
import '../cli/codex/provider_presets.dart';
import '../cli/cursor/provider_presets.dart';

/// Maps a Managed Provider `cli:<id>` credential source to the CLI provider
/// row used for login, import, and credential files.
class OfficialManagedProviderBinding {
  const OfficialManagedProviderBinding({
    required this.credentialSource,
    required this.cli,
    required this.appProviderId,
    required this.template,
  });

  final String credentialSource;
  final CliTool cli;
  final String appProviderId;
  final AppProviderConfig template;

  static OfficialManagedProviderBinding? forCredentialSource(String source) {
    switch (source.trim()) {
      case 'cli:openai-official':
        final preset = CodexProviderPresets.byId('openai-official');
        if (preset == null) return null;
        return OfficialManagedProviderBinding(
          credentialSource: 'cli:openai-official',
          cli: CliTool.codex,
          appProviderId: preset.template.id,
          template: preset.template,
        );
      case 'cli:claude-official':
        final preset = ClaudeProviderPresets.byId('claude-official');
        if (preset == null) return null;
        return OfficialManagedProviderBinding(
          credentialSource: 'cli:claude-official',
          cli: CliTool.claude,
          appProviderId: preset.template.id,
          template: preset.template,
        );
      case 'cli:cursor-account':
        final preset = CursorProviderPresets.byId('cursor-account');
        if (preset == null) return null;
        return OfficialManagedProviderBinding(
          credentialSource: 'cli:cursor-account',
          cli: CliTool.cursor,
          appProviderId: preset.template.id,
          template: preset.template,
        );
      default:
        return null;
    }
  }
}

Future<AppProviderConfig> ensureOfficialAppProvider({
  required AppProviderCubit cubit,
  required OfficialManagedProviderBinding binding,
}) async {
  final existing = cubit.state
      .providersFor(binding.cli)
      .where((provider) => provider.id == binding.appProviderId)
      .firstOrNull;
  if (existing != null) return existing;
  await cubit.upsertProvider(binding.template);
  return cubit.state
      .providersFor(binding.cli)
      .firstWhere((provider) => provider.id == binding.appProviderId);
}
