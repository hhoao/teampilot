import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/ssh_connection_cubit.dart';
import '../../cubits/ssh_profile_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/remote_target.dart';
import '../../models/ssh_profile.dart';
import '../../repositories/plane_ssh_profile_repository.dart';
import '../../repositories/remote_target_repository.dart';
import '../../repositories/ssh_credential_store.dart';
import '../../repositories/ssh_profile_repository.dart';
import '../../repositories/ssh_server_profile_repository.dart';
import '../../services/storage/home_storage.dart';
import '../../services/vault/credential_capture.dart';
import '../../utils/logging/logger.dart';
import '../../widgets/settings/workspace_pane_header.dart';
import '../ssh_profiles/ssh_profiles_section.dart';

/// SSH server management for the current home plane.
///
/// Same page and same actions as the desktop SSH servers page — add, import,
/// edit, test, connect, delete — but bound to the catalog stored *on the home
/// plane*: the remote host's own `remote-targets.json` merged with the shared
/// `ssh_profiles/profiles.json`. On a local home this is exactly the desktop
/// catalog; on a remote home it is that host's catalog. This device's own
/// targets never appear here, and every add/edit/delete executes on the plane,
/// so paired devices share the list.
///
/// Credentials and the live SSH transport cannot travel. A plane server is
/// registered in the device catalog only when the user connects to it, which is
/// what makes it show up under "Remote connections" — the mobile list of
/// connections this device has actually made.
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
  RemoteTargetRepository? _deviceTargets;
  SshProfileCubit? _deviceCubit;
  SshConnectionCubit? _connections;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_planeCubit != null) return;
    final storage = context.read<HomeStorage>();
    // Captured before the plane override below: this context is the device
    // catalog, the one the rest of the app and the connection layer use.
    _deviceTargets = context.read<SshProfileRepository>().targetRepo;
    _deviceCubit = context.read<SshProfileCubit>();
    _connections = context.read<SshConnectionCubit>();
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

  /// Registers a plane server in the device catalog right before connecting, so
  /// the connection layer knows it and it appears under "Remote connections".
  /// Servers merely browsed here are not recorded as connections.
  Future<bool> _registerConnection(SshProfile profile) async {
    final device = _deviceTargets;
    final deviceCubit = _deviceCubit;
    final connections = _connections;
    if (device == null || deviceCubit == null || connections == null) {
      return true;
    }
    try {
      if (await device.findById(profile.id) == null) {
        await device.save(
          RemoteTarget(
            id: profile.id,
            name: profile.name,
            host: profile.host,
            port: profile.port,
            username: profile.username,
            authType: profile.authType,
            embeddedTarget: profile.embeddedTarget,
            relayUrl: profile.relayUrl,
            pairedDesktopId: profile.pairedDesktopId,
            updatedAt: profile.updatedAt,
          ),
        );
      }
      await deviceCubit.load();
      await connections.syncProfiles(deviceCubit.state.profiles);
      return true;
    } on Object catch (error, stackTrace) {
      AppLogger.instance.w(
        '[ssh-servers] could not register the connection',
        error: error,
        stackTrace: stackTrace,
      );
      return true;
    }
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
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: SshProfilesSection(
                  showRemoteConfig: true,
                  beforeConnect: _registerConnection,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
