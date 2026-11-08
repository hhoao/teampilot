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
  StreamSubscription<StoragePlaneChange>? _planeSub;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final storage = context.read<HomeStorage>();
    _installPlane(storage);
    // A home switch replaces the plane this page is bound to: rebuild the
    // repository/cubit on the new context and reload instead of leaving the
    // previous host's catalog on screen.
    _planeSub = storage.changes.listen((_) {
      if (!mounted) return;
      _installPlane(storage, rebuild: true);
    });
  }

  void _installPlane(HomeStorage storage, {bool rebuild = false}) {
    final previous = _planeCubit;
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
    if (rebuild) setState(() {});
    if (previous != null) {
      // The swap is published to the tree first; retire the old cubit after the
      // frame that stops referencing it.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(previous.close());
      });
    }
  }

  @override
  void dispose() {
    unawaited(_planeSub?.cancel());
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
