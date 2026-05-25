import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../cubits/ssh_profile_cubit.dart';
import '../../../l10n/l10n_extensions.dart';
import '../../../repositories/ssh_credential_store.dart';
import '../../../repositories/ssh_profile_repository.dart';
import '../../../services/ssh/ssh_profile_connection_tester.dart';
import '../../../services/terminal/terminal_transport_factory.dart';
import '../../ssh_profile_setup_page.dart';

class OnboardingSshStep extends StatelessWidget {
  const OnboardingSshStep({super.key, required this.onContinue});

  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.onboardingSshTitle,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        Text(
          l10n.onboardingSshSubtitle,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 20),
        SshProfileSetupPage(
          profileRepository: context.read<SshProfileRepository>(),
          credentialStore: context.read<SshCredentialStore>(),
          connectionTester: SshProfileConnectionTester(
            clientFactory: context
                .read<TerminalTransportFactory>()
                .sshClientFactory,
          ),
          onProfileSaved: () {
            context.read<SshProfileCubit>().load();
            onContinue();
          },
        ),
      ],
    );
  }
}
