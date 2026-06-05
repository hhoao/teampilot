import '../../cubits/app_provider_cubit.dart';
import '../../cubits/team_cubit.dart';
import '../../models/app_provider_config.dart';
import '../../repositories/app_settings_repository.dart';

/// Decides whether the first-run setup wizard should appear.
///
/// Only [AppSettingsRepository.hasCompletedOnboarding] controls this gate.
/// Partial wizard progress (saved preferences, provider imports, etc.) does
/// not skip onboarding — the flag is written in [OnboardingGate] when the user
/// finishes the last step.
class OnboardingService {
  OnboardingService({required AppSettingsRepository appSettings})
    : _appSettings = appSettings;
  final AppSettingsRepository _appSettings;

  Future<bool> shouldShowOnboarding() async {
    return !(await _appSettings.loadHasCompletedOnboarding());
  }

  /// Binds the onboarding default Claude provider to Claude teams that have no
  /// team-level provider yet so [SessionLifecycleService] can resolve settings.
  static Future<void> applyDefaultClaudeProviderBinding({
    required AppProviderCubit appProviderCubit,
    required TeamCubit teamCubit,
  }) async {
    final providerId =
        appProviderCubit.state.selectedProviderIdByCli[CliTool.claude]
            ?.trim() ??
        '';
    if (providerId.isEmpty) return;

    final exists = appProviderCubit.state
        .providersFor(CliTool.claude)
        .any((provider) => provider.id == providerId);
    if (!exists) return;

    await teamCubit.bindClaudeProviderForTeamsWithoutBinding(providerId);
  }
}
