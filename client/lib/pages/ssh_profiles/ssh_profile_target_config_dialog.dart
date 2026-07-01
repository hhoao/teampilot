import 'package:flutter/material.dart';

import '../../l10n/l10n_extensions.dart';
import '../../models/runtime_target.dart';
import '../../models/ssh_profile.dart';
import '../../services/storage/targets_repository.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/settings/workspace_settings_widgets.dart';
import 'credential_push_opt_in_tile.dart';
import 'root_sandbox_env_opt_in_tile.dart';

/// Per-target connection options (credential push, root sandbox env).
Future<void> showSshProfileTargetConfigDialog(
  BuildContext context, {
  required SshProfile profile,
}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) {
      final cs = Theme.of(ctx).colorScheme;
      final tt = Theme.of(ctx).textTheme;
      return AppDialog(
        maxWidth: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppDialogHeader(title: ctx.l10n.configure),
            const SizedBox(height: 12),
            Text(
              profile.name,
              style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 2),
            Text(
              profile.hostIdentifier,
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            SettingsSurfaceCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SshProfileCredentialOptInTile(profile: profile),
                  SshProfileRootSandboxEnvOptInTile(
                    profile: profile,
                    showDividerBelow: false,
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );
}

/// P3c: per-profile credential-push opt-in for a target.
class SshProfileCredentialOptInTile extends StatefulWidget {
  const SshProfileCredentialOptInTile({
    super.key,
    required this.profile,
    this.showDividerBelow = true,
  });

  final SshProfile profile;
  final bool showDividerBelow;

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
      showDividerBelow: widget.showDividerBelow,
    );
  }
}

/// Per-profile root sandbox env opt-in for a target.
class SshProfileRootSandboxEnvOptInTile extends StatefulWidget {
  const SshProfileRootSandboxEnvOptInTile({
    super.key,
    required this.profile,
    this.showDividerBelow = true,
  });

  final SshProfile profile;
  final bool showDividerBelow;

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
      showDividerBelow: widget.showDividerBelow,
    );
  }
}
