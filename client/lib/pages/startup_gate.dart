import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../cubits/session_preferences_cubit.dart';
import '../cubits/ssh_profile_cubit.dart';
import '../services/app/connection_mode_service.dart';
import 'ssh_profiles_page.dart';
import 'termux/work_environment_chooser_page.dart';

class StartupGate extends StatelessWidget {
  const StartupGate({
    super.key,
    required this.child,
    this.isAndroid,
  });

  final Widget child;

  /// Test override; defaults to [Platform.isAndroid].
  final bool? isAndroid;

  @override
  Widget build(BuildContext context) {
    context.watch<SessionPreferencesCubit>();
    final mode = context.read<ConnectionModeService>();
    // Android needs a bound work home (Termux or SSH). Desktop local/wsl passes.
    final android = isAndroid ?? Platform.isAndroid;
    final androidNeedsWorkHome = android && !mode.hasBoundAndroidWorkHome;
    if (!mode.isRemoteWorkPlane && !androidNeedsWorkHome) return child;

    final sshState = context.watch<SshProfileCubit>().state;

    if (sshState.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (mode.requiresSshProfileSetup) {
      return const SshProfilesPage();
    }

    if (androidNeedsWorkHome) {
      return const WorkEnvironmentChooserPage();
    }

    return child;
  }
}
