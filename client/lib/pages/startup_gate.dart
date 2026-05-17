import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../cubits/ssh_profile_cubit.dart';
import '../repositories/ssh_credential_store.dart';
import '../repositories/ssh_profile_repository.dart';
import '../services/ssh_profile_connection_tester.dart';
import '../services/terminal_transport_factory.dart';
import 'ssh_profile_setup_page.dart';

class StartupGate extends StatelessWidget {
  const StartupGate({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!Platform.isAndroid) return child;

    final sshState = context.watch<SshProfileCubit>().state;

    if (sshState.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (!sshState.hasProfiles) {
      return SshProfileSetupPage(
        profileRepository: context.read<SshProfileRepository>(),
        credentialStore: context.read<SshCredentialStore>(),
        connectionTester: SshProfileConnectionTester(
          clientFactory: context
              .read<TerminalTransportFactory>()
              .sshClientFactory,
        ),
        onProfileSaved: () {
          context.read<SshProfileCubit>().load();
        },
      );
    }

    return child;
  }
}
