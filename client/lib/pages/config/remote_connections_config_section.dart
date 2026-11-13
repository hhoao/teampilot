import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/ssh_profile_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../repositories/ssh_profile_repository.dart';
import '../../widgets/settings/workspace_pane_header.dart';
import '../ssh_profiles/ssh_profiles_section.dart';

/// Device-local "remote connections" catalog: the always-available settings
/// surface for adding/editing targets, connecting, and switching home.
///
/// Unlike the startup gate's connection page (which shows a status card while
/// the home is down), this section is reachable at all times — including when
/// the SSH home is connected — because connection management lives on the
/// device, not on any remote host.
class RemoteConnectionsConfigSection extends StatelessWidget {
  const RemoteConnectionsConfigSection({this.showHeading = true, super.key});

  final bool showHeading;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showHeading)
          WorkspacePaneHeader(title: l10n.remote.connectionsTitle),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: BlocBuilder<SshProfileCubit, SshProfileState>(
              builder: (context, state) {
                final cubit = context.read<SshProfileCubit>();
                return SshProfilesSection(
                  profiles: state.profiles,
                  onRefresh: () => cubit.load(),
                  onDelete: cubit.deleteProfile,
                  repository: context.read<SshProfileRepository>(),
                  profileCubit: cubit,
                  showRemoteConfig: false,
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}
