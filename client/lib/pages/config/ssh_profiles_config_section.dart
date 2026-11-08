import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/ssh_profile_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../repositories/plane_ssh_profile_repository.dart';
import '../../repositories/ssh_credential_store.dart';
import '../../repositories/ssh_profile_repository.dart';
import '../../repositories/ssh_server_profile_repository.dart';
import '../../services/storage/home_storage.dart';
import '../../services/vault/credential_capture.dart';
import '../../widgets/settings/workspace_pane_header.dart';
import '../ssh_profiles/ssh_profiles_section.dart';

/// SSH servers page — the desktop page, reused on every platform.
///
/// Same widget, same actions, same title as the desktop settings entry. The
/// only difference is where its data lives: the current home plane. On a
/// desktop that plane *is* this machine, so the page is byte-identical to
/// before; on a phone whose home is a remote host, the very same page reads and
/// writes that host's catalog. This device's own connection targets are never
/// listed here — they belong to "Remote connections".
class SshProfilesConfigWorkspace extends StatefulWidget {
  const SshProfilesConfigWorkspace({this.showHeading = true, super.key});

  final bool showHeading;

  @override
  State<SshProfilesConfigWorkspace> createState() =>
      _SshProfilesConfigWorkspaceState();
}

class _SshProfilesConfigWorkspaceState extends State<SshProfilesConfigWorkspace> {
  SshProfileRepository? _planeRepository;
  SshProfileCubit? _planeCubit;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_planeCubit != null) return;
    final storage = context.read<HomeStorage>();
    final plane = PlaneSshProfileRepository(
      storage: storage,
      servers: SshServerProfileRepository(storage: storage),
    );
    _planeRepository = plane;
    _planeCubit = SshProfileCubit(
      profileRepository: plane,
      credentialStore: context.read<SshCredentialStore>(),
      vaultCapture: context.read<VaultCredentialCapture>(),
    )..load();
  }

  @override
  void dispose() {
    unawaited(_planeCubit?.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final repository = _planeRepository;
    final cubit = _planeCubit;
    if (repository == null || cubit == null) {
      return const SizedBox.shrink();
    }
    return RepositoryProvider<SshProfileRepository>.value(
      value: repository,
      child: BlocProvider<SshProfileCubit>.value(
        value: cubit,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.showHeading)
              WorkspacePaneHeader(title: context.l10n.sshProfilesPageTitle),
            const Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(16),
                child: SshProfilesSection(
                  showRemoteConfig: true,
                  // Desktop semantics: connect opens the host and keeps the
                  // current home. Switching home belongs to Remote connections.
                  switchHomeOnConnect: false,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
