import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../cubits/app_bootstrap_cubit.dart';
import '../../cubits/app_provider_cubit.dart';
import '../../cubits/chat_cubit.dart';
import '../../cubits/cli_presets_cubit.dart';
import '../../cubits/launch_profile_cubit.dart';
import '../../models/workspace.dart';
import '../../repositories/app_settings_repository.dart';
import '../../services/app/onboarding_service.dart';
import '../../services/storage/home_target_controller.dart';
import '../../services/team/default_workspace_service.dart';
import '../../utils/workspace/workspace_path_utils.dart';
import 'onboarding_wizard.dart';

/// App-wide handle for [OnboardingGateState]; wired in [appRouter].
final onboardingGateKey = GlobalKey<OnboardingGateState>();

class OnboardingGate extends StatefulWidget {
  const OnboardingGate({super.key, required this.child});

  final Widget child;

  @override
  State<OnboardingGate> createState() => OnboardingGateState();
}

class OnboardingGateState extends State<OnboardingGate> {
  var _reopenWizard = false;

  void completeOnboarding() {
    unawaited(_completeOnboarding());
  }

  Future<void> _completeOnboarding() async {
    if (!mounted) return;
    final appProviderCubit = context.read<AppProviderCubit>();
    final teamCubit = context.read<LaunchProfileCubit>();
    final cliPresetsCubit = context.read<CliPresetsCubit>();
    final settingsRepo = context.read<AppSettingsRepository>();
    await OnboardingService.finalizeOnboardingDefaults(
      cliPresetsCubit: cliPresetsCubit,
      launchProfileCubit: teamCubit,
      appProviderCubit: appProviderCubit,
    );
    await settingsRepo.saveHasCompletedOnboarding(true);
    if (!mounted) return;

    // Navigate to the default workspace landing page before dismissing the
    // wizard so the first frame after onboarding is the compose landing, not
    // the library home page.
    final home = context.read<HomeTargetController>().current;
    final primaryPath =
        await DefaultWorkspaceService.resolvePrimaryPath(home: home);
    if (mounted) {
      final chatCubit = context.read<ChatCubit>();
      Workspace? defaultWorkspace;
      for (final w in chatCubit.state.workspaces) {
        if (workspacePathsEqual(w.firstFolderPath, primaryPath)) {
          defaultWorkspace = w;
          break;
        }
      }
      if (defaultWorkspace != null) {
        GoRouter.of(context).go(
          '/home-v2/workspace/${defaultWorkspace.workspaceId}',
        );
      }
    }

    context.read<AppBootstrapCubit>().dismissOnboardingWizard();
    setState(() => _reopenWizard = false);
  }

  Future<void> reopenWizard() async {
    if (!mounted) return;
    await context.read<AppSettingsRepository>().saveHasCompletedOnboarding(
      false,
    );
    if (!mounted) return;
    setState(() => _reopenWizard = true);
  }

  @override
  Widget build(BuildContext context) {
    if (_reopenWizard) {
      return OnboardingWizard(onComplete: completeOnboarding);
    }

    final showWizard = context.select<AppBootstrapCubit, bool>(
      (cubit) => cubit.state.showOnboardingWizard,
    );
    if (showWizard) {
      return OnboardingWizard(onComplete: completeOnboarding);
    }
    return widget.child;
  }
}

/// Allows settings UI to re-open the setup wizard without restarting the app.
///
/// When [context] sits under a modal [Dialog] (e.g. the workspace settings
/// dialog), the dialog is closed first so the wizard is not hidden behind it.
Future<void> resetOnboardingWizard([BuildContext? context]) async {
  if (context != null &&
      context.findAncestorWidgetOfExactType<Dialog>() != null &&
      Navigator.of(context).canPop()) {
    Navigator.of(context).pop();
  }
  await onboardingGateKey.currentState?.reopenWizard();
}
