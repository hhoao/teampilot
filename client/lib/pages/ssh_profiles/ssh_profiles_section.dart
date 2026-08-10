import 'package:shared_ui/shared_ui.dart';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../widgets/app_toast/app_toast.dart';

import '../../cubits/ssh_connection_cubit.dart';
import '../../cubits/ssh_profile_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/ssh_profile.dart';
import '../../repositories/ssh_credential_store.dart';
import '../../services/ssh/ssh_connection_failure.dart';
import '../../services/ssh/ssh_profile_connection_tester.dart';
import '../../services/terminal/terminal_transport_factory.dart';
import '../ssh_profiles_page.dart';
import 'ssh_profile_connection_status.dart';
import 'ssh_profile_target_card.dart';
import 'ssh_profile_target_config_dialog.dart';

/// Orca-style SSH target list for settings (desktop + Android).
class SshProfilesSection extends StatefulWidget {
  const SshProfilesSection({super.key});

  @override
  State<SshProfilesSection> createState() => _SshProfilesSectionState();
}

class _SshProfilesSectionState extends State<SshProfilesSection> {
  final _testingIds = <String>{};

  /// Returns `null` on success, otherwise the caught failure.
  Future<Object?> _runTest(SshProfile profile, {bool showToast = true}) async {
    if (_testingIds.contains(profile.id)) {
      return StateError('SSH profile test already in progress');
    }
    setState(() => _testingIds.add(profile.id));
    try {
      final creds = await _loadCredentials(profile);
      final tester = SshProfileConnectionTester(
        clientFactory: context
            .read<TerminalTransportFactory>()
            .sshClientFactory,
      );
      await tester.test(
        profile,
        password: creds.password,
        privateKey: creds.privateKey,
        privateKeyPassphrase: creds.passphrase,
      );
      if (!mounted) return StateError('Widget unmounted');
      if (showToast) {
        AppToast.show(
          context,
          message: context.l10n.sshProfileTestSuccess,
          variant: TpToastVariant.success,
        );
      }
      return null;
    } on Object catch (e) {
      if (!mounted) return e;
      if (showToast) {
        AppToast.show(
          context,
          message: sshConnectionFailureUserMessage(e, context.l10n),
          variant: TpToastVariant.error,
        );
      }
      return e;
    } finally {
      if (mounted) setState(() => _testingIds.remove(profile.id));
    }
  }

  Future<void> _connect(SshProfile profile) async {
    await context.read<SshConnectionCubit>().connect(profile.id);
    if (!mounted) return;
    final host = context
        .read<SshConnectionCubit>()
        .state
        .hostsById[profile.id];
    if (host?.status == SshHostUiStatus.connected) {
      AppToast.show(
        context,
        message: context.l10n.sshProfileConnectSuccess(profile.host),
        variant: TpToastVariant.success,
      );
    } else if (host != null &&
        (host.status == SshHostUiStatus.error ||
            host.status == SshHostUiStatus.authFailed) &&
        host.errorDetail != null &&
        host.errorDetail!.isNotEmpty) {
      AppToast.show(
        context,
        message: host.errorDetail!,
        variant: TpToastVariant.error,
      );
    }
  }

  void _disconnect(SshProfile profile) {
    context.read<SshConnectionCubit>().disconnect(profile.id);
  }

  Future<({String? password, String? privateKey, String? passphrase})>
  _loadCredentials(SshProfile profile) async {
    final store = context.read<SshCredentialStore>();
    if (profile.authType == SshAuthType.password) {
      return (
        password: await store.loadPassword(profile.id),
        privateKey: null,
        passphrase: null,
      );
    }
    return (
      password: null,
      privateKey: await store.loadPrivateKey(profile.id),
      passphrase: await store.loadPrivateKeyPassphrase(profile.id),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = context.watch<SshProfileCubit>().state;
    final connectionState = context.watch<SshConnectionCubit>().state;
    final profiles = state.profiles;

    return TpCard.outlined(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.sshProfilesTargetsTitle,
                        style: TpTextStyles.of(context).mdBoldTightSnug,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        l10n.sshProfilesTargetsSubtitle,
                        style: TpTextStyles.of(context).mutedSm,
                      ),
                    ],
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () {
                    AppToast.show(
                      context,
                      message: l10n.sshProfilesImportUnavailable,
                      variant: TpToastVariant.info,
                    );
                  },
                  icon: const Icon(Icons.upload_outlined, size: 18),
                  label: Text(l10n.sshProfilesImport),
                ),
                const SizedBox(width: 8),
                FilledButton.tonalIcon(
                  onPressed: () => openSshProfileEditor(context),
                  icon: const Icon(Icons.add, size: 18),
                  label: Text(l10n.sshProfilesAddTarget),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (state.isLoading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (profiles.isEmpty)
              Container(
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(
                  vertical: 28,
                  horizontal: 16,
                ),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  l10n.sshProfilesEmpty,
                  style: TpTextStyles.of(context).mutedMd,
                ),
              )
            else
              for (final profile in profiles)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: SshProfileTargetCard(
                    profile: profile,
                    status:
                        connectionState.hostsById[profile.id]?.status ??
                        SshProfileConnectionStatus.disconnected,
                    statusError:
                        connectionState.hostsById[profile.id]?.errorDetail,
                    testing: _testingIds.contains(profile.id),
                    busy: false,
                    onTest: () => _runTest(profile),
                    onConnect: () => _connect(profile),
                    onDisconnect: () => _disconnect(profile),
                    onEdit: () =>
                        openSshProfileEditor(context, profile: profile),
                    onDelete: () => confirmDeleteSshProfile(context, profile),
                    onRefresh: () => context.read<SshProfileCubit>().load(),
                    onConfigure: () => showSshProfileTargetConfigDialog(
                      context,
                      profile: profile,
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}
