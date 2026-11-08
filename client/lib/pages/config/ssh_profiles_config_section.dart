import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/ssh_profile_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/remote_target.dart';
import '../../repositories/ssh_profile_repository.dart';
import '../../repositories/ssh_server_profile_repository.dart';
import '../../services/storage/home_storage.dart';
import '../../utils/logging/logger.dart';
import '../../widgets/settings/workspace_pane_header.dart';
import '../ssh_profiles/ssh_profiles_section.dart';

/// SSH server management for the current home plane.
///
/// Shows the same full-featured list as the original SSH servers page: add,
/// edit, test, connect, and delete. The catalog is the home plane's one, so
/// servers configured on the host behind the current home are visible even
/// before this device has connected to them: on mount, any server that exists
/// only on the plane is mirrored into the device-local target catalog (without
/// credentials), which is what every row action operates on. Credentials stay
/// on the device and are entered through the editor on first use.
class SshProfilesConfigWorkspace extends StatefulWidget {
  const SshProfilesConfigWorkspace({this.showHeading = true, super.key});

  final bool showHeading;

  @override
  State<SshProfilesConfigWorkspace> createState() =>
      _SshProfilesConfigWorkspaceState();
}

class _SshProfilesConfigWorkspaceState extends State<SshProfilesConfigWorkspace> {
  bool _mirrorStarted = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_mirrorStarted) return;
    _mirrorStarted = true;
    _mirrorPlaneServers();
  }

  /// Materializes plane-only servers into the device-local target catalog so
  /// the shared row actions (test/connect/edit/delete) can manage them. Entries
  /// already known locally are left untouched.
  Future<void> _mirrorPlaneServers() async {
    try {
      final storage = context.read<HomeStorage>();
      final profileCubit = context.read<SshProfileCubit>();
      final targets = context.read<SshProfileRepository>().targetRepo;
      final remote = await SshServerProfileRepository(
        storage: storage,
      ).loadAll();
      if (remote.isEmpty) return;
      final known = (await targets.loadAll()).map((t) => t.id).toSet();
      var added = false;
      for (final server in remote) {
        if (known.contains(server.id)) continue;
        await targets.save(
          RemoteTarget(
            id: server.id,
            name: server.name,
            host: server.host,
            port: server.port,
            username: server.username,
            authType: server.authType,
            embeddedTarget: server.embeddedTarget,
            relayUrl: server.relayUrl,
            pairedDesktopId: server.pairedDesktopId,
            updatedAt: server.updatedAt,
          ),
        );
        added = true;
      }
      if (added) await profileCubit.load();
    } on Object catch (error, stackTrace) {
      // Never let a mirroring problem hide the catalog the user does have.
      AppLogger.instance.w(
        '[ssh-servers] could not mirror home-plane servers',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
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
    );
  }
}
