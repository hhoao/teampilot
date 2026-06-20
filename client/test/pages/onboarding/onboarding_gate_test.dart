import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/pages/onboarding/onboarding_gate.dart';
import 'package:teampilot/repositories/app_settings_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('onboardingGateKey reaches reopenWizard on OnboardingGate', (
    tester,
  ) async {
    final settings = InMemoryAppSettingsRepository(
      hasCompletedOnboarding: true,
    );

    await tester.pumpWidget(
      RepositoryProvider<AppSettingsRepository>.value(
        value: settings,
        child: MaterialApp(
          home: OnboardingGate(
            key: onboardingGateKey,
            child: const Scaffold(body: Text('main app')),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(onboardingGateKey.currentState, isNotNull);
    await onboardingGateKey.currentState!.reopenWizard();

    expect(await settings.loadHasCompletedOnboarding(), isFalse);
  });

  testWidgets('resetOnboardingWizard pops enclosing dialog before gate call', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => Dialog(
                  child: Builder(
                    builder: (dialogChildContext) => TextButton(
                      onPressed: () => resetOnboardingWizard(dialogChildContext),
                      child: const Text('rerun setup'),
                    ),
                  ),
                ),
              ),
              child: const Text('open dialog'),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('open dialog'));
    await tester.pump();
    expect(find.byType(Dialog), findsOneWidget);

    await tester.tap(find.text('rerun setup'));
    await tester.pump();

    expect(find.byType(Dialog), findsNothing);
  });
}
