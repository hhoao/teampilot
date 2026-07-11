import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../cubits/ssh_profile_cubit.dart';
import '../../../l10n/l10n_extensions.dart';
import '../../../repositories/ssh_credential_store.dart';
import '../../../repositories/ssh_profile_repository.dart';
import '../../../services/ssh/ssh_profile_connection_tester.dart';
import '../../../services/terminal/terminal_transport_factory.dart';
import '../../ssh_profile_setup_page.dart';
import '../../../theme/app_text_styles.dart';

class OnboardingSshStep extends StatelessWidget {
  const OnboardingSshStep({
    super.key,
    this.isActive = true,
    required this.onContinue,
  });

  final bool isActive;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.onboardingSshTitle,
          style: AppTextStyles.of(context).display,
        ),
        const SizedBox(height: 8),
        Text(
          l10n.onboardingSshSubtitle,
          style: AppTextStyles.of(context).mutedMd,
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
