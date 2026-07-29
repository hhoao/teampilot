import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../cubits/session_preferences_cubit.dart';
import '../cubits/ssh_profile_cubit.dart';
import '../services/app/connection_mode_service.dart';
import 'ssh_profiles_page.dart';

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
    // Android can only run over SSH: it must have an ssh home target. Desktop
    // with a local/wsl home needs no gate.
    final android = isAndroid ?? Platform.isAndroid;
    final androidNeedsSshHome = android && !mode.isSshMode;
    if (!mode.isSshMode && !androidNeedsSshHome) return child;

    final sshState = context.watch<SshProfileCubit>().state;

    if (sshState.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (mode.requiresSshProfileSetup || androidNeedsSshHome) {
      return const SshProfilesPage();
    }

    return child;
  }
}
