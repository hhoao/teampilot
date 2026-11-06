import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../cubits/ssh_connection_cubit.dart';
import '../cubits/ssh_profile_cubit.dart';
import '../cubits/ssh_server_config_cubit.dart';
import '../l10n/l10n_extensions.dart';
import '../models/ssh_profile.dart';
import '../models/ssh_server_profile.dart';
import '../repositories/ssh_credential_store.dart';
import '../repositories/ssh_profile_repository.dart';
import '../repositories/ssh_server_profile_repository.dart';
import '../services/ssh/ssh_profile_connection_tester.dart';
import '../services/storage/home_storage.dart';
import '../services/terminal/terminal_transport_factory.dart';
import '../services/vault/vault_service.dart';
import 'ssh_profile_setup_page.dart';
import 'ssh_profiles/ssh_profile_form_dialog.dart';

/// Remote-only catalog of SSH server configurations.
///
/// When there is no live remote connection the page is intentionally inert:
/// no connect action, no add-target action, and no list. Once connected it
/// shows the read-only remote profiles from [SshServerConfigCubit].
class SshServersPage extends StatelessWidget {
  const SshServersPage({super.key, this.embedded = false});

  /// When true, omits the [Scaffold] so the surrounding shell supplies chrome.
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    return BlocProvider<SshServerConfigCubit>(
      create: (_) => SshServerConfigCubit(
        repository: SshServerProfileRepository(
          storage: context.read<HomeStorage>(),
        ),
      )..load(),
      child: _SshServersView(embedded: embedded),
    );
  }
}

class _SshServersView extends StatelessWidget {
  const _SshServersView({required this.embedded});

  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final connected = context.watch<SshConnectionCubit>().state.connectedHosts;
    final Widget body;
    if (connected.isEmpty) {
      body = Center(child: Text(l10n.sshServersNotConnected));
    } else {
      body = BlocBuilder<SshServerConfigCubit, SshServerConfigState>(
        builder: (context, state) {
          if (state.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          return ListView(
            children: [
              for (final profile in state.profiles)
                SshServerProfileCard(profile: profile),
            ],
          );
        },
      );
    }
    if (embedded) return body;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.sshServersTitle)),
      body: body,
    );
  }
}

/// Read-only presentation of a single remote [SshServerProfile].
///
/// Shows the name, host and whether it is an embedded target. It deliberately
/// offers no editing: [SshServerProfile] carries no editable config fields and
/// the per-target editor operates on the local `SshProfile` model instead.
class SshServerProfileCard extends StatelessWidget {
  const SshServerProfileCard({super.key, required this.profile});

  final SshServerProfile profile;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(profile.name),
      subtitle: Text(profile.host),
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
  bool? useFullPageEditor,
}) async {
  final fullPage = useFullPageEditor ?? Platform.isAndroid;
  if (fullPage) {
    VaultService? vaultService;
    try {
      vaultService = context.read<VaultService>();
    } on ProviderNotFoundException {
      vaultService = null;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SshProfileSetupPage(
          profileRepository: context.read<SshProfileRepository>(),
          credentialStore: context.read<SshCredentialStore>(),
          initialProfile: profile,
          vaultService: vaultService,
          connectionTester: SshProfileConnectionTester(
            clientFactory: context
                .read<TerminalTransportFactory>()
                .sshClientFactory,
          ),
          onProfileSaved: () {
            Navigator.of(context).maybePop();
            context.read<SshProfileCubit>().load();
          },
        ),
      ),
    );
    return;
  }
  await showSshProfileFormDialog(context, profile: profile);
}

Future<void> confirmDeleteSshProfile(
  BuildContext context,
  SshProfile profile,
) async {
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
  await context.read<SshProfileCubit>().deleteProfile(profile.id);
}
