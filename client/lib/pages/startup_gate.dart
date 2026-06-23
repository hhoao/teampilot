import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../cubits/session_preferences_cubit.dart';
import '../cubits/ssh_profile_cubit.dart';
import '../services/app/connection_mode_service.dart';
import '../services/storage/home_target_controller.dart';
import '../repositories/ssh_credential_store.dart';
import '../repositories/ssh_profile_repository.dart';
import '../services/ssh/ssh_profile_connection_tester.dart';
import '../services/terminal/terminal_transport_factory.dart';
import 'ssh_profile_setup_page.dart';

class StartupGate extends StatelessWidget {
  const StartupGate({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    context.watch<SessionPreferencesCubit>();
    final mode = context.read<ConnectionModeService>();
    // Android can only run over SSH: it must have an ssh home target. Desktop
    // with a local/wsl home needs no gate.
    final androidNeedsSshHome = Platform.isAndroid && !mode.isSshMode;
    if (!mode.isSshMode && !androidNeedsSshHome) return child;

    final sshState = context.watch<SshProfileCubit>().state;

    if (sshState.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (mode.requiresSshProfileSetup || androidNeedsSshHome) {
      return SshProfileSetupPage(
        profileRepository: context.read<SshProfileRepository>(),
        credentialStore: context.read<SshCredentialStore>(),
        connectionTester: SshProfileConnectionTester(
          clientFactory: context
              .read<TerminalTransportFactory>()
              .sshClientFactory,
        ),
        onProfileSaved: () async {
          final sshCubit = context.read<SshProfileCubit>();
          final homeController = context.read<HomeTargetController>();
          await sshCubit.load();
          // On Android the freshly created profile becomes the home target.
          if (Platform.isAndroid && sshCubit.state.profiles.isNotEmpty) {
            await homeController.select('ssh:${sshCubit.state.profiles.first.id}');
          }
        },
      );
    }

    return child;
  }
}
