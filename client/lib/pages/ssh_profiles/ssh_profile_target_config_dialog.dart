import 'package:flutter/material.dart';

import '../../l10n/l10n_extensions.dart';
import '../../models/runtime_target.dart';
import '../../models/ssh_profile.dart';
import '../../services/storage/targets_repository.dart';
import 'package:shared_ui/shared_ui.dart';
import 'credential_push_opt_in_tile.dart';

/// Per-target connection options (credential push).
Future<void> showSshProfileTargetConfigDialog(
  BuildContext context, {
  required SshProfile profile,
}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) {
      return TpDialog(
        maxWidth: 680,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TpDialogHeader(title: ctx.l10n.configure),
            const SizedBox(height: 12),
            TpCard.outlined(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SshProfileCredentialOptInTile(
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
