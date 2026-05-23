import '../repositories/app_settings_repository.dart';

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
}
