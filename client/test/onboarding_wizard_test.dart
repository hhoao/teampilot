import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:teampilot/pages/onboarding/onboarding_wizard.dart';
import 'package:teampilot/repositories/app_settings_repository.dart';
import 'package:teampilot/services/onboarding_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('onboardingStepsForPlatform', () {
    test('desktop has four steps without SSH', () {
      expect(onboardingStepsForPlatform(), hasLength(4));
      expect(onboardingStepsForPlatform(), isNot(contains(OnboardingStepKind.ssh)));
    });
  });

  group('OnboardingService', () {
    test('shows wizard for fresh install', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final service = OnboardingService(
        appSettings: SharedPrefsAppSettingsRepository(prefs),
        preferences: prefs,
      );

      expect(await service.shouldShowOnboarding(), isTrue);
    });

    test('skips wizard when session preferences already exist', () async {
      SharedPreferences.setMockInitialValues({
        'flashskyai.session_preferences.v1': '{"connectionMode":"localPty"}',
      });
      final prefs = await SharedPreferences.getInstance();
      final repo = SharedPrefsAppSettingsRepository(prefs);
      final service = OnboardingService(
        appSettings: repo,
        preferences: prefs,
      );

      expect(await service.shouldShowOnboarding(), isFalse);
      expect(await repo.loadHasCompletedOnboarding(), isTrue);
    });
  });
}
