import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/ssh_profile_cubit.dart';
import '../../cubits/ssh_workload_profile_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../repositories/plane_ssh_profile_repository.dart';
import '../../repositories/ssh_server_profile_repository.dart';
import '../../services/storage/home_storage.dart';
import '../../widgets/settings/workspace_pane_header.dart';
import '../ssh_profiles/ssh_profiles_section.dart';

/// SSH servers page — the desktop page, reused on every platform.
///
/// Same widget, same actions, same title as the desktop settings entry. Its
/// data is the global home-plane (B source) workload catalog from Task 1: a
/// single long-lived [SshWorkloadProfileCubit] injected at the app root, which
/// owns the `HomeStorage.changes` reload. This device's own connection targets
/// belong to "Remote connections" (A source) and are never listed here.
class SshProfilesConfigWorkspace extends StatelessWidget {
  const SshProfilesConfigWorkspace({this.showHeading = true, super.key});

  final bool showHeading;

  @override
  Widget build(BuildContext context) {
    final storage = context.read<HomeStorage>();
    // The editor's writes go to the shared home-plane catalog. Vault-reference
    // lending for the *list* is handled by the global workload cubit's own
    // read, so this write repository needs no device-target facade.
    final repository = PlaneSshProfileRepository(
      storage: storage,
      servers: SshServerProfileRepository(storage: storage),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showHeading)
          WorkspacePaneHeader(title: context.l10n.sshProfile.sPageTitle),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: BlocBuilder<SshWorkloadProfileCubit, SshProfileState>(
              builder: (context, state) => SshProfilesSection(
                profiles: state.profiles,
                onRefresh: () =>
                    context.read<SshWorkloadProfileCubit>().load(),
                repository: repository,
                profileCubit: context.read<SshWorkloadProfileCubit>(),
                showRemoteConfig: true,
                // Desktop semantics: connect opens the host and keeps the
                // current home. Switching home belongs to Remote connections.
                switchHomeOnConnect: false,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
