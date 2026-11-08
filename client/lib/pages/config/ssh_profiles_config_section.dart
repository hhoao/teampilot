import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/ssh_profile_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/remote_target.dart';
import '../../repositories/remote_target_repository.dart';
import '../../repositories/ssh_credential_store.dart';
import '../../repositories/plane_ssh_profile_repository.dart';
import '../../repositories/ssh_profile_repository.dart';
import '../../repositories/ssh_server_profile_repository.dart';
import '../../services/storage/home_storage.dart';
import '../../services/vault/credential_capture.dart';
import '../../utils/logging/logger.dart';
import '../../widgets/settings/workspace_pane_header.dart';
import '../ssh_profiles/ssh_profiles_section.dart';

/// SSH server management for the current home plane.
///
/// This is the same full-featured list as the normal SSH servers page — add,
/// import, edit, test, connect, delete — but bound to the catalog stored *on
/// the home plane*: the remote host's own `remote-targets.json` merged with the
/// shared `ssh_profiles/profiles.json`. This device's own targets never appear
/// here, and every add/edit/delete executes on the home plane, so the list is
/// shared by every device paired to it.
///
/// Credentials and the live SSH transport cannot travel, so plane entries are
/// mirrored into the device catalog without credentials: that is what lets the
/// shared row actions test and connect. Missing credentials are entered through
/// the editor on first use.
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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_planeCubit != null) return;
    final storage = context.read<HomeStorage>();
    // Captured before the plane override below: this context is the device
    // catalog, the one the rest of the app and the connection layer use.
    _deviceTargets = context.read<SshProfileRepository>().targetRepo;
    _deviceCubit = context.read<SshProfileCubit>();
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
    _mirrorPlaneServers();
  }

  @override
  void dispose() {
    unawaited(_planeCubit?.close());
    super.dispose();
  }

  /// Mirrors plane-only servers into the device catalog without credentials so
  /// test/connect can run against them. The page itself still lists the plane
  /// catalog, so local-only targets never show up here.
  Future<void> _mirrorPlaneServers() async {
    final plane = _planeRepository;
    final device = _deviceTargets;
    final deviceCubit = _deviceCubit;
    if (plane == null || device == null || deviceCubit == null) return;
    try {
      final planes = await plane.loadAll();
      if (planes.isEmpty) return;
      final known = (await device.loadAll()).map((t) => t.id).toSet();
      var added = false;
      for (final profile in planes) {
        if (known.contains(profile.id)) continue;
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
        added = true;
      }
      if (added) await deviceCubit.load();
    } on Object catch (error, stackTrace) {
      // Never let mirroring hide the catalog the user does have.
      AppLogger.instance.w(
        '[ssh-servers] could not mirror home-plane servers',
        error: error,
        stackTrace: stackTrace,
      );
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
            const Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(16),
                child: SshProfilesSection(showRemoteConfig: true),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
