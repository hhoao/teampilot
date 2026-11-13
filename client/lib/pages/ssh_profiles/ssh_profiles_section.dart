import 'package:shared_ui/shared_ui.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../widgets/app_toast/app_toast.dart';

import '../../cubits/ssh_connection_cubit.dart';
import '../../cubits/ssh_profile_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/ssh_profile.dart';
import '../../repositories/ssh_credential_store.dart';
import '../../repositories/ssh_profile_repository.dart';
import '../../services/ssh/android_ssh_connect_home.dart';
import '../../services/ssh/ssh_connection_failure.dart';
import '../../services/ssh/ssh_credentials_resolver.dart';
import '../../services/ssh/ssh_profile_connection_tester.dart';
import '../../services/vault/credential_capture.dart';
import '../../services/vault/vault_service.dart';
import '../../services/vault/vault_unlock_gate.dart';
import '../../services/storage/home_storage.dart';
import '../../services/storage/home_target_controller.dart';
import '../../services/terminal/terminal_transport_factory.dart';
import '../../utils/ui/app_keys.dart';
import '../connect/android_pair_sheet.dart';
import '../ssh_profiles_page.dart';
import 'ssh_profile_connection_status.dart';
import 'ssh_profile_target_card.dart';
import 'ssh_profile_target_config_dialog.dart';

/// Orca-style SSH target list for settings (desktop + Android).
///
/// The profile source is injected: callers pass the profiles to render, a
/// refresh callback, the repository edits write through, and the cubit backing
/// them. The device-local A source ([SshProfileCubit]) and the home-plane B
/// source (the global workload cubit) both emit [SshProfileState], so the
/// section stays agnostic about where its rows come from.
class SshProfilesSection extends StatefulWidget {
  const SshProfilesSection({
    super.key,
    required this.profiles,
    required this.onRefresh,
    required this.onDelete,
    required this.repository,
    required this.profileCubit,
    this.showRemoteConfig = true,
    this.switchHomeOnConnect = true,
    this.homeBindingMode = false,
  });

  /// Rows to render, supplied by the owning page's profile source.
  final List<SshProfile> profiles;

  /// Reloads the injected source after a write (e.g. `cubit.load()`).
  final Future<void> Function() onRefresh;

  /// Deletes a row from the injected source. Supplied by the owning page so
  /// the A source keeps credential/vault cleanup and the B source deletes the
  /// shared plane record, without this widget inspecting the source type.
  final Future<void> Function(String profileId) onDelete;

  /// Repository the editor writes new/edited profiles through.
  final SshProfileRepository repository;

  /// Cubit backing [profiles]; typed to the shared [SshProfileState] supertype
  /// so both the A-source [SshProfileCubit] and the B-source workload cubit fit.
  final Cubit<SshProfileState> profileCubit;

  /// The "remote config" editor operates on a local [SshProfile], not the
  /// remote server model. The SSH-servers page passes `true`; the
  /// remote-connections surfaces pass `false`. It is retained for the follow-up
  /// spec that adds full remote-config editing (credential push / port-forward
  /// / root sandbox); the connection behaviour is unchanged for now.
  final bool showRemoteConfig;

  /// Android Connect rebinds the home plane to the connected host. Applies
  /// only to the workload (non-[homeBindingMode]) connect path, which goes
  /// through [SshConnectionCubit.connect]: the SSH-servers page passes
  /// `false` so its connect keeps the current home.
  final bool switchHomeOnConnect;

  /// When `true`, Connect performs a pure home binding instead of opening an
  /// [SshConnectionCubit] connection: it selects the SSH home target
  /// (`ssh:<id>`) and persists the selected profile through
  /// [applyAndroidSshConnectHome]. The remote-connections surfaces (A source,
  /// home-binding) set this; the SSH-servers page (B source, workload) leaves
  /// it `false` and keeps `connect(id, switchHome: false)`. This is the single
  /// explicit mode switch — no platform checks are scattered through the
  /// connect path.
  final bool homeBindingMode;

  @override
  State<SshProfilesSection> createState() => _SshProfilesSectionState();
}

class _SshProfilesSectionState extends State<SshProfilesSection> {
  final _testingIds = <String>{};

  Future<void> _openEditor(BuildContext context, {SshProfile? profile}) {
    return openSshProfileEditor(
      context,
      profile: profile,
      repository: widget.repository,
      profileCubit: widget.profileCubit,
      onRefresh: widget.onRefresh,
    );
  }

  Future<void> _deleteProfile(BuildContext context, SshProfile profile) {
    return confirmDeleteSshProfile(
      context,
      profile,
      onDelete: widget.onDelete,
    );
  }

  /// Returns `null` on success, otherwise the caught failure.
  Future<Object?> _runTest(SshProfile profile, {bool showToast = true}) async {
    if (_testingIds.contains(profile.id)) {
      return StateError('SSH profile test already in progress');
    }
    if (!await _ensureVaultUnlockedFor(profile)) {
      return const VaultSaveBlockedException();
    }
    if (!mounted) return StateError('Widget unmounted');
    setState(() => _testingIds.add(profile.id));
    try {
      final clientFactory = context
          .read<TerminalTransportFactory>()
          .sshClientFactory;
      final creds = await _loadCredentials(profile);
      final tester = SshProfileConnectionTester(clientFactory: clientFactory);
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
          message: context.l10n.sshProfile.testSuccess,
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
    if (!await _ensureVaultUnlockedFor(profile)) return;
    if (!mounted) return;
    if (widget.homeBindingMode) {
      // Pure home binding: rebind the home plane to this host and persist the
      // selected profile. No SshConnectionCubit.connect — the home-plane
      // switch reconnects the host through its own connect(pid) path, and the
      // device-local A host never reaches the B-only status bar.
      await applyAndroidSshConnectHome(
        profileId: profile.id,
        selectHome: context.read<HomeTargetController>().select,
        selectProfile: context.read<SshProfileCubit>().selectProfile,
      );
      return;
    }
    await context.read<SshConnectionCubit>().connect(
      profile.id,
      switchHome: widget.switchHomeOnConnect,
    );
    if (!mounted) return;
    final host = context.read<SshConnectionCubit>().state.hostsById[profile.id];
    if (host?.status == SshHostUiStatus.connected) {
      AppToast.show(
        context,
        message: context.l10n.sshProfile.connectSuccess(host: profile.host),
        variant: TpToastVariant.success,
      );
    } else if (host != null &&
        (host.status == SshHostUiStatus.error ||
            host.status == SshHostUiStatus.authFailed) &&
        host.errorDetail != null &&
        host.errorDetail!.isNotEmpty) {
      AppToast.show(
        context,
        message: sshErrorDetailUserMessage(host.errorDetail, context.l10n),
        variant: TpToastVariant.error,
      );
    }
  }

  void _disconnect(SshProfile profile) {
    context.read<SshConnectionCubit>().disconnect(profile.id);
  }

  /// Vault-backed targets need an unlocked vault before their secret can be
  /// read. Prompting here keeps connect/test from failing with a generic auth
  /// error; a cancelled prompt aborts the action.
  Future<bool> _ensureVaultUnlockedFor(SshProfile profile) async {
    if ((profile.vaultEntryId ?? '').trim().isEmpty) return true;
    final vault = _vaultService();
    if (vault == null || vault.isUnlocked) return true;
    VaultUnlockGate? gate;
    try {
      gate = context.read<VaultUnlockGate>();
    } on ProviderNotFoundException {
      gate = null;
    }
    final unlocked = gate != null && await gate.ensureUnlocked();
    if (!unlocked) {
      if (mounted) {
        AppToast.show(
          context,
          message: context.l10n.vault.lockedSaveBlocked,
          variant: TpToastVariant.error,
        );
      }
      return false;
    }
    return true;
  }

  Future<({String? password, String? privateKey, String? passphrase})>
  _loadCredentials(SshProfile profile) async {
    final store = context.read<SshCredentialStore>();
    final vault = _vaultService();
    final resolvedEntryId = vault == null
        ? null
        : await _vaultEntryIdFor(profile, vault);
    final effective = resolvedEntryId == null
        ? profile
        : profile.copyWith(vaultEntryId: resolvedEntryId);
    final resolved = await resolveSshCredentials(
      effective,
      vault: vault == null
          ? null
          : (entryId, field) => vault.readField(entryId, field),
      legacyPassword: store.loadPassword,
      legacyPrivateKey: store.loadPrivateKey,
      legacyPassphrase: store.loadPrivateKeyPassphrase,
    );
    return (
      password: resolved.password,
      privateKey: resolved.privateKey,
      passphrase: resolved.passphrase,
    );
  }

  /// Recovers the device vault entry for a profile whose catalog record cannot
  /// carry the reference.
  ///
  /// The "SSH servers" page reads the home-plane server catalog, whose records
  /// deliberately have no `vaultEntryId`: the secret stays on the device that
  /// saved it. Without this lookup the row would resolve credentials from the
  /// legacy keychain only — empty after a vault-backed save — leaving every
  /// test/connect with no password at all.
  Future<String?> _vaultEntryIdFor(
    SshProfile profile,
    VaultService vault,
  ) async {
    final linked = (profile.vaultEntryId ?? '').trim();
    if (linked.isNotEmpty) return linked;
    try {
      final entry = await findVaultOwnerEntry(
        vault,
        ownerKind: vaultOwnerKindSshProfile,
        ownerId: profile.id,
      );
      return entry?.id;
    } on Object {
      // A locked or unreachable vault must not break the keychain fallback.
      return null;
    }
  }

  VaultService? _vaultService() {
    try {
      return context.read<VaultService>();
    } on ProviderNotFoundException {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final connectionState = context.watch<SshConnectionCubit>().state;
    final profiles = widget.profiles;
    final isLoading = widget.profileCubit.state.isLoading;
    final isAndroid = defaultTargetPlatform == TargetPlatform.android;
    final heading = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.sshProfile.sTargetsTitle,
          style: TpTextStyles.of(context).mdBoldTightSnug,
        ),
        const SizedBox(height: 4),
        Text(
          l10n.sshProfile.sTargetsSubtitle,
          style: TpTextStyles.of(context).mutedSm,
        ),
      ],
    );

    return TpCard.outlined(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (isAndroid)
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  heading,
                  const SizedBox(height: 14),
                  Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(
                        key: AppKeys.connectScanQr,
                        onPressed: () => showAndroidPairSheet(context),
                        icon: const Icon(Icons.qr_code_scanner, size: 18),
                        label: Text(l10n.connect.scanQr),
                      ),
                      FilledButton.tonalIcon(
                        onPressed: () => _openEditor(context),
                        icon: const Icon(Icons.add, size: 18),
                        label: Text(l10n.sshProfile.sAddTarget),
                      ),
                    ],
                  ),
                ],
              )
            else
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(child: heading),
                  OutlinedButton.icon(
                    onPressed: () {
                      AppToast.show(
                        context,
                        message: l10n.sshProfile.sImportUnavailable,
                        variant: TpToastVariant.info,
                      );
                    },
                    icon: const Icon(Icons.upload_outlined, size: 18),
                    label: Text(l10n.sshProfile.sImport),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.tonalIcon(
                    onPressed: () => _openEditor(context),
                    icon: const Icon(Icons.add, size: 18),
                    label: Text(l10n.sshProfile.sAddTarget),
                  ),
                ],
              ),
            const SizedBox(height: 16),
            if (isLoading)
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
                  l10n.sshProfile.sEmpty,
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
                    onEdit: () => _openEditor(context, profile: profile),
                    onDelete: () => _deleteProfile(context, profile),
                    onRefresh: () => widget.onRefresh(),
                    onConfigure: widget.showRemoteConfig
                        ? () => showSshProfileTargetConfigDialog(
                            context,
                            profile: profile,
                            storage: context.read<HomeStorage>(),
                          )
                        : null,
                  ),
                ),
          ],
        ),
      ),
    );
  }
}
