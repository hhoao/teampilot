import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../cubits/ssh_profile_cubit.dart';
import '../cubits/ssh_server_config_cubit.dart';
import '../l10n/l10n_extensions.dart';
import '../models/ssh_profile.dart';
import '../repositories/ssh_profile_repository.dart';
import '../repositories/catalog_store.dart';
import '../repositories/plane_ssh_profile_repository.dart';
import '../services/storage/home_storage.dart';
import 'ssh_profiles/ssh_profile_form_dialog.dart';

/// Remote-only catalog of SSH server configurations.
///
/// Reads `<home>/ssh_profiles/profiles.json` from the current home plane, so
/// the list is the one stored on the remote host itself. It is available
/// whenever the home plane is a remote (SSH) one — it does not depend on a
/// session-level `connectedHosts` entry, which is a different plane. Switching
/// the home plane reloads the catalog.
class SshServersPage extends StatefulWidget {
  const SshServersPage({super.key, this.embedded = false});

  /// When true, omits the [Scaffold] so the surrounding shell supplies chrome.
  final bool embedded;

  @override
  State<SshServersPage> createState() => _SshServersPageState();
}

class _SshServersPageState extends State<SshServersPage> {
  StreamSubscription<StoragePlaneChange>? _planeSub;
  late final HomeStorage _storage;
  late final SshServerConfigCubit _cubit;
  late bool _onRemoteHome;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_planeSub != null) return;
    _storage = context.read<HomeStorage>();
    _onRemoteHome = _storage.fs.isRemote;
    _cubit = SshServerConfigCubit(
      repository: PlaneSshProfileRepository(
        storage: _storage,
        connections: context.read<SshProfileRepository>().connectionStore,
        catalog: CatalogStore(storage: _storage),
      ),
    )..load();
    // A home switch publishes a new plane; the catalog lives on that plane, so
    // re-evaluate the gate and reload instead of showing the previous host's
    // servers.
    _planeSub = _storage.changes.listen((change) {
      if (!mounted) return;
      setState(() => _onRemoteHome = change.newContext.filesystem.isRemote);
      unawaited(_cubit.load());
    });
  }

  @override
  void dispose() {
    unawaited(_planeSub?.cancel());
    unawaited(_cubit.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider<SshServerConfigCubit>.value(
      value: _cubit,
      child: _SshServersView(
        embedded: widget.embedded,
        onRemoteHome: _onRemoteHome,
      ),
    );
  }
}

class _SshServersView extends StatelessWidget {
  const _SshServersView({required this.embedded, required this.onRemoteHome});

  final bool embedded;
  final bool onRemoteHome;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    // The catalog belongs to the home plane, not to session connections: an
    // SSH home is remote even when no member session is connected.
    final Widget body;
    if (!onRemoteHome) {
      body = Center(child: Text(l10n.ssh.serversNotConnected));
    } else {
      body = BlocBuilder<SshServerConfigCubit, SshServerConfigState>(
        builder: (context, state) {
          if (state.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          // A remote transport failure emits error with an empty catalog. Show
          // a distinct message + retry instead of an empty ListView that looks
          // exactly like "no servers".
          if (state.error != null) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(l10n.ssh.serversLoadError),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: () =>
                        context.read<SshServerConfigCubit>().load(),
                    child: Text(l10n.retry),
                  ),
                ],
              ),
            );
          }
          if (state.profiles.isEmpty && state.needsConnection.isEmpty) {
            return Center(child: Text(l10n.ssh.serversEmpty));
          }
          return ListView(
            children: [
              for (final profile in state.profiles)
                SshServerProfileCard(profile: profile),
              if (state.needsConnection.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
                  child: Text(
                    l10n.ssh.serversNeedsConnectionHint,
                    style: TpTextStyles.of(context).mutedSm,
                  ),
                ),
                for (final entry in state.needsConnection)
                  ListTile(
                    leading: const Icon(Icons.link_off, size: 18),
                    title: Text(entry.displayName),
                    subtitle: Text(l10n.ssh.serversNotConnectedOnDevice),
                  ),
              ],
            ],
          );
        },
      );
    }
    if (embedded) return body;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.ssh.serversTitle)),
      body: body,
    );
  }
}

/// Read-only presentation of a machine the plane lists and this device can
/// reach.
///
/// Shows the full shared configuration (host:port, username, auth type, relay
/// and pairing). It deliberately offers no editing: the record is read from the
/// home plane and credentials never live here.
class SshServerProfileCard extends StatelessWidget {
  const SshServerProfileCard({super.key, required this.profile});

  final SshProfile profile;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final authLabel = switch (profile.authType) {
      SshAuthType.password => l10n.sshProfile.formPassword,
      SshAuthType.privateKey => l10n.vault.typeSshPrivateKey,
    };
    return ListTile(
      isThreeLine: true,
      title: Text(profile.name),
      subtitle: Text(
        '${profile.username}@${profile.host}:${profile.port} · $authLabel'
        '${profile.relayUrl != null ? '\n${profile.relayUrl}' : ''}'
        '${profile.pairedDesktopId != null ? '\n${profile.pairedDesktopId}' : ''}',
      ),
      trailing: Icon(
        profile.embeddedTarget
            ? Icons.check_circle_outline
            : Icons.radio_button_unchecked,
        size: 18,
      ),
    );
  }
}

Future<void> openSshProfileEditor(
  BuildContext context, {
  SshProfile? profile,
  required SshProfileRepository repository,
  required Cubit<SshProfileState> profileCubit,
  required Future<void> Function() onRefresh,
}) async {
  await showSshProfileFormDialog(
    context,
    profile: profile,
    repository: repository,
    profileCubit: profileCubit,
    onRefresh: onRefresh,
  );
}

/// Confirms and performs a delete through the caller-supplied [onDelete].
/// The source is explicit in that callback (A source → full
/// `SshProfileCubit.deleteProfile` with credential/vault cleanup; B source →
/// `repository.delete(id)` + source reload), so no runtime type inspection or
/// implicit context lookup is needed here.
Future<void> confirmDeleteSshProfile(
  BuildContext context,
  SshProfile profile, {
  required Future<void> Function(String profileId) onDelete,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => TpDialog(
      maxWidth: 480,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const TpDialogHeader(title: '删除 SSH Profile'),
          const SizedBox(height: 16),
          Text('确定删除 ${profile.name} 吗？保存的凭据也会一并删除。'),
          TpDialogActions(
            children: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('删除'),
              ),
            ],
          ),
        ],
      ),
    ),
  );
  if (confirmed != true || !context.mounted) return;
  await onDelete(profile.id);
}
