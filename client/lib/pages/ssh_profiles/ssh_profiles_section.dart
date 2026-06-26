import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:teampilot/theme/app_toast_theme.dart';
import 'package:teampilot/widgets/app_toast/app_toast.dart';

import '../../cubits/ssh_profile_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/runtime_target.dart';
import '../../models/ssh_profile.dart';
import '../../repositories/ssh_credential_store.dart';
import '../../services/ssh/ssh_profile_connection_tester.dart';
import '../../services/storage/targets_repository.dart';
import '../../services/terminal/terminal_transport_factory.dart';
import '../../widgets/settings/workspace_settings_widgets.dart';
import '../ssh_profile_setup_page.dart';
import '../ssh_profiles_page.dart';
import 'credential_push_opt_in_tile.dart';
import 'root_sandbox_env_opt_in_tile.dart';
import 'ssh_profile_connection_status.dart';
import 'ssh_profile_target_card.dart';

/// Orca-style SSH target list for settings (desktop + Android).
class SshProfilesSection extends StatefulWidget {
  const SshProfilesSection({super.key});

  @override
  State<SshProfilesSection> createState() => _SshProfilesSectionState();
}

class _SshProfilesSectionState extends State<SshProfilesSection> {
  final _statusById = <String, SshProfileConnectionStatus>{};
  final _errorById = <String, String>{};
  final _testingIds = <String>{};
  final _busyIds = <String>{};

  SshProfileConnectionStatus _statusOf(String id) =>
      _statusById[id] ?? SshProfileConnectionStatus.disconnected;

  void _setStatus(String id, SshProfileConnectionStatus status, {String? error}) {
    setState(() {
      _statusById[id] = status;
      if (error == null) {
        _errorById.remove(id);
      } else {
        _errorById[id] = error;
      }
    });
  }

  Future<bool> _runTest(SshProfile profile, {bool showToast = true}) async {
    if (_testingIds.contains(profile.id)) return false;
    setState(() => _testingIds.add(profile.id));
    _setStatus(profile.id, SshProfileConnectionStatus.connecting);
    try {
      final creds = await _loadCredentials(profile);
      final tester = SshProfileConnectionTester(
        clientFactory: context.read<TerminalTransportFactory>().sshClientFactory,
      );
      await tester.test(
        profile,
        password: creds.password,
        privateKey: creds.privateKey,
        privateKeyPassphrase: creds.passphrase,
      );
      if (!mounted) return false;
      _setStatus(profile.id, SshProfileConnectionStatus.connected);
      if (showToast) {
        AppToast.show(
          context,
          message: context.l10n.sshProfileTestSuccess,
          variant: AppToastVariant.success,
        );
      }
      return true;
    } on Object catch (e) {
      if (!mounted) return false;
      _setStatus(
        profile.id,
        SshProfileConnectionStatus.error,
        error: e.toString(),
      );
      if (showToast) {
        AppToast.show(
          context,
          message: context.l10n.sshProfileTestFailed,
          variant: AppToastVariant.error,
        );
      }
      return false;
    } finally {
      if (mounted) setState(() => _testingIds.remove(profile.id));
    }
  }

  Future<void> _connect(SshProfile profile) async {
    if (_busyIds.contains(profile.id)) return;
    setState(() => _busyIds.add(profile.id));
    try {
      if (Platform.isAndroid) {
        _setStatus(profile.id, SshProfileConnectionStatus.connecting);
        await context.read<SshProfileCubit>().selectProfile(profile.id);
        if (!mounted) return;
        _setStatus(profile.id, SshProfileConnectionStatus.connected);
      } else {
        final ok = await _runTest(profile, showToast: false);
        if (!mounted) return;
        if (!ok) {
          AppToast.show(
            context,
            message: context.l10n.sshProfileTestFailed,
            variant: AppToastVariant.error,
          );
          return;
        }
      }
      if (!mounted) return;
      AppToast.show(
        context,
        message: context.l10n.sshProfileConnectSuccess(profile.host),
        variant: AppToastVariant.success,
      );
    } on Object catch (e) {
      if (!mounted) return;
      _setStatus(
        profile.id,
        SshProfileConnectionStatus.error,
        error: e.toString(),
      );
    } finally {
      if (mounted) setState(() => _busyIds.remove(profile.id));
    }
  }

  void _disconnect(SshProfile profile) {
    _setStatus(profile.id, SshProfileConnectionStatus.disconnected);
  }

  Future<({
    String? password,
    String? privateKey,
    String? passphrase,
  })> _loadCredentials(SshProfile profile) async {
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
    final profiles = state.profiles;

    return SettingsSurfaceCard(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.sshProfilesTargetsTitle,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        l10n.sshProfilesTargetsSubtitle,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () {
                    AppToast.show(
                      context,
                      message: l10n.sshProfilesImportUnavailable,
                      variant: AppToastVariant.info,
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
                padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  l10n.sshProfilesEmpty,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              )
            else
              for (final profile in profiles)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: SshProfileTargetCard(
                    profile: profile,
                    status: _statusOf(profile.id),
                    statusError: _errorById[profile.id],
                    testing: _testingIds.contains(profile.id),
                    busy: _busyIds.contains(profile.id),
                    onTest: () => _runTest(profile),
                    onConnect: () => _connect(profile),
                    onDisconnect: () => _disconnect(profile),
                    onEdit: () => openSshProfileEditor(context, profile: profile),
                    onDelete: () => confirmDeleteSshProfile(context, profile),
                    onRefresh: () => context.read<SshProfileCubit>().load(),
                    footer: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SshProfileCredentialOptInTile(profile: profile),
                        SshProfileRootSandboxEnvOptInTile(profile: profile),
                      ],
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

/// P3c: per-profile credential-push opt-in under each target card.
class SshProfileCredentialOptInTile extends StatefulWidget {
  const SshProfileCredentialOptInTile({super.key, required this.profile});

  final SshProfile profile;

  @override
  State<SshProfileCredentialOptInTile> createState() =>
      _SshProfileCredentialOptInTileState();
}

class _SshProfileCredentialOptInTileState
    extends State<SshProfileCredentialOptInTile> {
  final _repo = TargetsRepository();
  bool _optedIn = false;

  String get _targetId => RuntimeTarget.ssh(widget.profile.id, label: '').id;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final value = await _repo.isCredentialOptIn(_targetId);
    if (mounted) setState(() => _optedIn = value);
  }

  Future<void> _onChanged(bool next) async {
    await _repo.setCredentialOptIn(_targetId, next);
    if (mounted) setState(() => _optedIn = next);
  }

  @override
  Widget build(BuildContext context) {
    return CredentialPushOptInTile(
      host: widget.profile.host,
      optedIn: _optedIn,
      onChanged: _onChanged,
    );
  }
}

/// Per-profile root sandbox env opt-in under each target card.
class SshProfileRootSandboxEnvOptInTile extends StatefulWidget {
  const SshProfileRootSandboxEnvOptInTile({super.key, required this.profile});

  final SshProfile profile;

  @override
  State<SshProfileRootSandboxEnvOptInTile> createState() =>
      _SshProfileRootSandboxEnvOptInTileState();
}

class _SshProfileRootSandboxEnvOptInTileState
    extends State<SshProfileRootSandboxEnvOptInTile> {
  final _repo = TargetsRepository();
  bool _optedIn = false;

  String get _targetId => RuntimeTarget.ssh(widget.profile.id, label: '').id;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final value = await _repo.isRootSandboxEnvOptIn(_targetId);
    if (mounted) setState(() => _optedIn = value);
  }

  Future<void> _onChanged(bool next) async {
    await _repo.setRootSandboxEnvOptIn(_targetId, next);
    if (mounted) setState(() => _optedIn = next);
  }

  @override
  Widget build(BuildContext context) {
    return RootSandboxEnvOptInTile(
      host: widget.profile.host,
      optedIn: _optedIn,
      onChanged: _onChanged,
    );
  }
}
