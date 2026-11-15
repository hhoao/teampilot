import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../l10n/l10n_extensions.dart';
import '../../models/ssh_profile.dart';
import '../../models/install_job/install_cancel_policy.dart';
import '../../models/install_job/install_job_key.dart';
import '../../models/install_job/install_job_scope.dart';
import '../../models/install_job/install_job_spec.dart';
import '../../services/acp/acp_proxy_install.dart';
import '../../services/acp/acp_proxy_route.dart';
import '../../services/cli/installer_types.dart';
import '../../services/cli/registry/cli_tool_registry.dart';
import '../../services/install/install_job_registry.dart';
import '../../services/remote/remote_profile_context.dart';
import '../../services/ssh/ssh_client_factory.dart';
import '../../utils/ui/app_keys.dart';
import '../../widgets/app_toast/app_toast.dart';

/// Machine-level ACP proxy card. Shown only for a remote SSH workspace.
class AcpProxyMachineCard extends StatefulWidget {
  const AcpProxyMachineCard({this.loadStatus, this.runAction, super.key});

  /// Test seam. Production reads `acp-proxy.json` over SSH.
  final Future<AcpProxyProbeSnapshot> Function()? loadStatus;

  /// Test seam. Production downloads or starts the proxy over SSH.
  final Future<CliInstallResult> Function(AcpProxyCardAction action)? runAction;

  @override
  State<AcpProxyMachineCard> createState() => _AcpProxyMachineCardState();
}

class _AcpProxyMachineCardState extends State<AcpProxyMachineCard> {
  AcpProxyProbeSnapshot? _snapshot;
  String? _error;
  var _loading = true;
  var _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_refresh());
    });
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final load = widget.loadStatus ?? _loadProduction;
      final snapshot = await load();
      if (!mounted) return;
      setState(() {
        _snapshot = snapshot;
        _loading = false;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  Future<AcpProxyProbeSnapshot> _loadProduction() async {
    final profile = remoteSshProfileFromContext(context);
    if (profile == null) {
      throw StateError(context.l10n.cli.acpProxyNoSsh);
    }
    final result = await _runScript(
      context.read<SshClientFactory>(),
      profile,
      acpProxyProbeScript(),
    );
    if (result.exitCode != 0) {
      throw StateError(
        result.stderr.trim().isEmpty ? result.stdout.trim() : result.stderr,
      );
    }
    return parseAcpProxyProbe(result.stdout);
  }

  Future<void> _act(AcpProxyCardAction action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final run = widget.runAction;
      final result = run != null
          ? await run(action)
          : await _runProduction(action);
      if (!mounted) return;
      if (!result.success) {
        setState(() => _error = result.message);
        AppToast.show(
          context,
          message: result.message,
          variant: TpToastVariant.error,
        );
        return;
      }
      await _refresh();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<CliInstallResult> _runProduction(AcpProxyCardAction action) async {
    final profile = remoteSshProfileFromContext(context);
    if (profile == null) {
      return CliInstallResult(
        success: false,
        message: context.l10n.cli.acpProxyNoSsh,
      );
    }
    final remote = switch (action) {
      AcpProxyCardAction.install => AcpProxyRemoteAction.install,
      AcpProxyCardAction.update => AcpProxyRemoteAction.update,
      AcpProxyCardAction.start => AcpProxyRemoteAction.start,
      AcpProxyCardAction.ready => null,
    };
    if (remote == null) {
      return const CliInstallResult(success: true, message: 'ready');
    }
    final factory = context.read<SshClientFactory>();
    final jobs = context.read<InstallJobRegistry>();
    final installer = AcpProxyRemoteInstaller(
      cliIds: acpProxyCliIds(CliToolRegistry.builtIn()),
    );
    final l10n = context.l10n;
    return jobs.enqueue(
      InstallJobSpec<CliInstallResult>(
        key: InstallJobKey(
          kind: InstallJobKind.cliExecutable,
          target: 'acp-proxy',
          scope: InstallJobScopeSsh(profile.id),
        ),
        title: l10n.cli.acpProxyTitle,
        cancelPolicy: InstallCancelPolicy.cooperative,
        run: (ctx) => installer.run(remote, (script) async {
          ctx.reportPhase(l10n.cli.installProgressDownloading);
          return _runScript(
            factory,
            profile,
            script,
            timeout: const Duration(minutes: 5),
          );
        }),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final styles = TpTextStyles.of(context);
    final action = _snapshot == null
        ? null
        : acpProxyCardActionForProbe(_snapshot!);
    final buttonLabel = _error != null
        ? l10n.cli.acpProxyRetry
        : switch (action) {
            AcpProxyCardAction.install => l10n.cli.installButton,
            AcpProxyCardAction.update => l10n.cli.upgradeButton,
            AcpProxyCardAction.start => l10n.cli.acpProxyStart,
            AcpProxyCardAction.ready || null => null,
          };
    final status = _loading
        ? l10n.cli.acpProxyChecking
        : _error != null
        ? _error!
        : switch (action) {
            AcpProxyCardAction.install => l10n.cli.acpProxyMissing,
            AcpProxyCardAction.update => l10n.cli.acpProxyOutdated,
            AcpProxyCardAction.start => l10n.cli.acpProxyStopped,
            AcpProxyCardAction.ready => l10n.cli.readinessReady,
            null => l10n.cli.acpProxyChecking,
          };
    return TpCard.outlined(
      key: AppKeys.acpProxyMachineCard,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.cli.acpProxyTitle, style: styles.lgSemiboldSnug),
            const SizedBox(height: 6),
            Text(l10n.cli.acpProxySubtitle, style: styles.mutedMd),
            const SizedBox(height: 12),
            Text(status, style: styles.md),
            if (buttonLabel != null) ...[
              const SizedBox(height: 12),
              OutlinedButton(
                key: AppKeys.acpProxyActionButton,
                onPressed: _busy || _loading
                    ? null
                    : () {
                        if (_error != null) {
                          unawaited(_refresh());
                          return;
                        }
                        final next = action;
                        if (next != null && next != AcpProxyCardAction.ready) {
                          unawaited(_act(next));
                        }
                      },
                child: Text(_busy ? l10n.cli.installInstalling : buttonLabel),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

Future<CliInstallerCommandResult> _runScript(
  SshClientFactory factory,
  SshProfile profile,
  String script, {
  Duration timeout = const Duration(seconds: 30),
}) async {
  try {
    final result = await factory.runOnStorage(
      profile,
      CliInstallerCommand.unixShellScript(script).commandLine,
      timeout: timeout,
    );
    return CliInstallerCommandResult(
      exitCode: result.exitCode ?? 0,
      stdout: utf8.decode(result.stdout, allowMalformed: true),
      stderr: utf8.decode(result.stderr, allowMalformed: true),
    );
  } on Object catch (error) {
    return CliInstallerCommandResult(exitCode: 1, stderr: error.toString());
  }
}
