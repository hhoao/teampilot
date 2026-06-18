import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/app_provider_cubit.dart';
import '../../cubits/launch_profile_cubit.dart';
import '../../repositories/app_settings_repository.dart';
import '../../services/app/onboarding_service.dart';
import '../../theme/workspace_surface_layers.dart';
import 'onboarding_wizard.dart';

class OnboardingGate extends StatefulWidget {
  const OnboardingGate({super.key, required this.child});

  final Widget child;

  @override
  State<OnboardingGate> createState() => OnboardingGateState();
}

class OnboardingGateState extends State<OnboardingGate> {
  bool? _showWizard;
  late final OnboardingService _onboardingService;

  @override
  void initState() {
    super.initState();
    _onboardingService = OnboardingService(
      appSettings: context.read<AppSettingsRepository>(),
    );
    unawaited(_resolve());
  }

  Future<void> _resolve() async {
    final show = await _onboardingService.shouldShowOnboarding();
    if (!mounted) return;
    setState(() => _showWizard = show);
  }

  void completeOnboarding() {
    unawaited(_completeOnboarding());
  }

  Future<void> _completeOnboarding() async {
    if (!mounted) return;
    final appProviderCubit = context.read<AppProviderCubit>();
    final teamCubit = context.read<LaunchProfileCubit>();
    final settingsRepo = context.read<AppSettingsRepository>();
    await OnboardingService.applyDefaultClaudeProviderBinding(
      appProviderCubit: appProviderCubit,
      teamCubit: teamCubit,
    );
    await settingsRepo.saveHasCompletedOnboarding(true);
    if (!mounted) return;
    setState(() => _showWizard = false);
  }

  Future<void> reopenWizard() async {
    if (!mounted) return;
    await context.read<AppSettingsRepository>().saveHasCompletedOnboarding(false);
    if (!mounted) return;
    setState(() => _showWizard = true);
  }

  @override
  Widget build(BuildContext context) {
    final showWizard = _showWizard;
    if (showWizard == null) {
      final cs = Theme.of(context).colorScheme;
      return Scaffold(
        backgroundColor: cs.workspacePage,
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (showWizard) {
      return OnboardingWizard(onComplete: completeOnboarding);
    }
    return widget.child;
  }
}

/// Allows settings UI to re-open the setup wizard without restarting the app.
Future<void> resetOnboardingWizard(BuildContext context) async {
  await context.findAncestorStateOfType<OnboardingGateState>()?.reopenWizard();
}
