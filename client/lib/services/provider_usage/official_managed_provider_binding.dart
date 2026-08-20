import '../../cubits/app_provider_cubit.dart';
import '../../models/app_provider_config.dart';
import '../cli/claude/provider_presets.dart';
import '../cli/codex/provider_presets.dart';
import 'adapters/claude_subscription_adapter.dart';
import 'adapters/codex_subscription_adapter.dart';

/// Maps a Managed Provider official adapter to the CLI provider row used for
/// login, import, and credential files.
class OfficialManagedProviderBinding {
  const OfficialManagedProviderBinding({
    required this.adapterId,
    required this.cli,
    required this.appProviderId,
    required this.template,
  });

  final String adapterId;
  final CliTool cli;
  final String appProviderId;
  final AppProviderConfig template;

  static OfficialManagedProviderBinding? forAdapter(String adapterId) {
    switch (adapterId.trim()) {
      case CodexSubscriptionAdapter.stableAdapterId:
        final preset = CodexProviderPresets.byId('openai-official');
        if (preset == null) return null;
        return OfficialManagedProviderBinding(
          adapterId: CodexSubscriptionAdapter.stableAdapterId,
          cli: CliTool.codex,
          appProviderId: preset.template.id,
          template: preset.template,
        );
      case ClaudeSubscriptionAdapter.stableAdapterId:
        final preset = ClaudeProviderPresets.byId('claude-official');
        if (preset == null) return null;
        return OfficialManagedProviderBinding(
          adapterId: ClaudeSubscriptionAdapter.stableAdapterId,
          cli: CliTool.claude,
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
