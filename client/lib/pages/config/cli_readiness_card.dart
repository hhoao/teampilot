import 'dart:async';
import 'dart:io' show Platform;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/session_preferences_cubit.dart';
import '../../cubits/ssh_profile_cubit.dart';
import '../../cubits/termux_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/cli_binary_kind.dart';
import '../../models/install_job/install_job_key.dart';
import '../../models/ssh_profile.dart';
import '../../models/team_config.dart';
import '../../services/app/connection_mode_service.dart';
import '../../services/cli/acp_adapter_discovery.dart';
import '../../services/cli/installer_types.dart';
import '../../services/cli/cli_executable_discovery.dart';
import '../../services/cli/cli_version_probe.dart';
import '../../services/cli/codex/capabilities/acp_adapter_installer.dart';
import '../../services/cli/remote_cli_locator.dart';
import '../../services/cli/registry/capabilities/acp_capability.dart';
import '../../services/cli/registry/capabilities/acp_settings_capability.dart';
import '../../services/cli/registry/cli_tool_registry.dart';
import '../../services/cli/registry/installer/npm_installer_capability.dart';
import '../../services/install/install_job_enqueue.dart';
import '../../services/install/install_job_keys.dart';
import '../../services/install/install_job_registry.dart';
import '../../services/install/install_job_scope_resolver.dart';
import '../../services/ssh/ssh_client_factory.dart';
import '../../services/termux/termux_transport_profile.dart';
import '../../theme/app_fonts.dart';
import '../../utils/ui/app_keys.dart';
import '../../widgets/app_toast/app_toast.dart';
import '../../widgets/cli/cli_brand_icon.dart';

enum CliReadinessChipKind { ready, updateAvailable, needsSetup }

CliReadinessChipKind readinessChip({
  required bool cliKnown,
  required bool needsAdapter,
  required bool adapterKnown,
  required bool cliUpdate,
  required bool adapterUpdate,
}) {
  if (!cliKnown || (needsAdapter && !adapterKnown)) {
    return CliReadinessChipKind.needsSetup;
  }
  if (cliUpdate || adapterUpdate) return CliReadinessChipKind.updateAvailable;
  return CliReadinessChipKind.ready;
}

bool isNpmUpdate({required String? installed, required String? latest}) {
  if (installed == null || latest == null) return false;
  return installed.trim() != latest.trim();
}

class CliReadinessCard extends StatefulWidget {
  const CliReadinessCard({
    required this.cli,
    required this.cubit,
    this.isAndroidOverride,
    this.versionProbe,
    super.key,
  });

  final CliTool cli;
  final SessionPreferencesCubit cubit;
  final bool? isAndroidOverride;
  final CliVersionProbe? versionProbe;

  @override
  State<CliReadinessCard> createState() => _CliReadinessCardState();
}

class _CliReadinessCardState extends State<CliReadinessCard> {
  late final CliVersionProbe _probe;
  bool _locatingCli = false;
  bool _locatingAdapter = false;

  CliToolRegistry get _registry => CliToolRegistry.builtIn();

  bool get _isAndroid => widget.isAndroidOverride ?? Platform.isAndroid;

  CliExecutableCapability? get _executable =>
      _registry.capability<CliExecutableCapability>(widget.cli);

  AcpSettingsCapability? get _settings =>
      _registry.capability<AcpSettingsCapability>(widget.cli);

  bool get _hasAcp =>
      _registry.capability<AcpCapability>(widget.cli) != null ||
      _settings != null;

  bool get _separateAdapter => _settings?.usesSeparateAdapter == true;

  @override
  void initState() {
    super.initState();
    _probe = widget.versionProbe ?? CliVersionProbe();
    if (!_isAndroid) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_refreshLatest());
      });
    }
  }

  NpmInstallerCapability? _npmInstaller(CliExecutableCapability? exec) {
    return exec is NpmInstallerCapability
        ? exec as NpmInstallerCapability
        : null;
  }

  Future<void> _refreshLatest() async {
    final npm = _npmInstaller(_executable);
    if (npm != null) {
      final latest = await _probe.latestNpm(npm.npmPackage);
      if (!mounted) return;
      if (latest != null) {
        widget.cubit.mergeBinaryVersion(
          cli: widget.cli,
          kind: CliBinaryKind.cli,
          latest: latest,
        );
      }
    }
    final adapter = _settings?.adapterInstaller;
    if (adapter != null) {
      final latest = await _probe.latestNpm(adapter.npmPackage);
      if (!mounted) return;
      if (latest != null) {
        widget.cubit.mergeBinaryVersion(
          cli: widget.cli,
          kind: CliBinaryKind.adapter,
          latest: latest,
        );
      }
    }
  }

  Future<void> _probeInstalled(CliBinaryKind kind, String path) async {
    if (!_looksAbsolute(path)) return;
    final version = await _probe.installed(path);
    if (!mounted || version == null) return;
    widget.cubit.mergeBinaryVersion(
      cli: widget.cli,
      kind: kind,
      installed: version,
    );
  }

  static bool _looksAbsolute(String value) =>
      value.contains('/') || value.contains(r'\');

  InstallJobKey _cliJobKey(BuildContext context) {
    return InstallJobKeys.cli(
      widget.cli.value,
      scope: installJobScopeForContext(context),
    );
  }

  InstallJobKey _adapterJobKey() {
    final installer = _settings?.adapterInstaller;
    if (installer is CodexAcpAdapterInstaller) {
      return InstallJobKeys.codexAcpAdapter();
    }
    return InstallJobKeys.claudeAcpAdapter();
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.any);
    final picked = result?.files.single.path;
    if (picked == null || !mounted) return;
    await widget.cubit.setCliExecutablePathFor(widget.cli, picked);
    await _probeInstalled(CliBinaryKind.cli, picked);
  }

  Future<void> _resetCliPath() async {
    await widget.cubit.setCliExecutablePathFor(widget.cli, '');
  }

  Future<void> _locateCli() async {
    final jobs = context.read<InstallJobRegistry>();
    if (_locatingCli || jobs.isRunning(_cliJobKey(context))) return;
    setState(() => _locatingCli = true);
    final title = _executable?.label(context.l10n) ?? widget.cli.value;
    try {
      final path = (await _resolveCliLocatePath())?.trim() ?? '';
      if (!mounted) return;
      if (path.isEmpty) {
        AppToast.show(
          context,
          message: context.l10n.cliExecutablePathLocateFailed(title),
          variant: TpToastVariant.error,
        );
        return;
      }
      await widget.cubit.setCliExecutablePathFor(widget.cli, path);
      if (_looksAbsolute(path)) {
        widget.cubit.mergeLocatedExecutables({widget.cli: path});
      }
      await _probeInstalled(CliBinaryKind.cli, path);
      if (!mounted) return;
      AppToast.show(
        context,
        message: context.l10n.cliExecutablePathLocateSuccess(title, path),
        variant: TpToastVariant.success,
      );
    } catch (_) {
      if (!mounted) return;
      AppToast.show(
        context,
        message: context.l10n.cliExecutablePathLocateFailed(title),
        variant: TpToastVariant.error,
      );
    } finally {
      if (mounted) setState(() => _locatingCli = false);
    }
  }

  Future<String?> _resolveCliLocatePath() async {
    final connectionMode = context.read<ConnectionModeService>();
    if (connectionMode.isRemoteWorkPlane) {
      final profile = _remoteSshProfile(context, connectionMode);
      if (profile == null) return null;
      final client = await context.read<SshClientFactory>().clientForStorage(
        profile,
      );
      return CliExecutableDiscovery().locateRemoteCli(
        cli: widget.cli,
        run: RemoteCliLocator.getRunnerForClient(client),
      );
    }
    return CliExecutableDiscovery().locateLocalCli(widget.cli);
  }

  Future<void> _installOrUpgradeCli({required bool upgrading}) async {
    final jobs = context.read<InstallJobRegistry>();
    final scope = installJobScopeForContext(context);
    final title = upgrading
        ? context.l10n.cliInstallUpgrading
        : context.l10n.cliInstallInstalling;
    setState(() {});
    try {
      final result = await jobs.installCli(
        cli: widget.cli,
        scope: scope,
        title: title,
        onSucceeded: (installResult) async {
          final path = installResult.executablePath?.trim() ?? '';
          if (path.isEmpty) return;
          if (_looksAbsolute(path)) {
            widget.cubit.mergeLocatedExecutables({widget.cli: path});
          }
          await widget.cubit.setCliExecutablePathFor(widget.cli, path);
          await _probeInstalled(CliBinaryKind.cli, path);
        },
      );
      if (!mounted) return;
      AppToast.show(
        context,
        message: result.message,
        variant: result.success ? TpToastVariant.success : TpToastVariant.error,
      );
    } catch (error) {
      if (!mounted) return;
      AppToast.show(
        context,
        message: error.toString(),
        variant: TpToastVariant.error,
      );
    } finally {
      if (mounted) setState(() {});
    }
  }

  Future<void> _locateAdapter() async {
    if (_locatingAdapter) return;
    setState(() => _locatingAdapter = true);
    try {
      final found = await AcpAdapterDiscovery(registry: _registry).locateLocal();
      final path = found[widget.cli]?.trim() ?? '';
      if (!mounted) return;
      if (!_looksAbsolute(path)) {
        AppToast.show(
          context,
          message: context.l10n.cliReadinessAdapterMissing,
          variant: TpToastVariant.error,
        );
        return;
      }
      widget.cubit.mergeLocatedAcpAdapters({widget.cli: path});
      await _probeInstalled(CliBinaryKind.adapter, path);
    } finally {
      if (mounted) setState(() => _locatingAdapter = false);
    }
  }

  Future<void> _installOrUpgradeAdapter({required bool upgrading}) async {
    final jobs = context.read<InstallJobRegistry>();
    final title = upgrading
        ? context.l10n.cliInstallUpgrading
        : context.l10n.cliInstallInstalling;
    setState(() {});
    try {
      final installer = _settings?.adapterInstaller;
      Future<void> onSucceeded(CliInstallResult installResult) async {
        final path = installResult.executablePath?.trim() ?? '';
        if (path.isEmpty || !_looksAbsolute(path)) return;
        widget.cubit.mergeLocatedAcpAdapters({widget.cli: path});
        await _probeInstalled(CliBinaryKind.adapter, path);
      }

      final result = installer is CodexAcpAdapterInstaller
          ? await jobs.installCodexAcpAdapter(
              title: title,
              onSucceeded: onSucceeded,
            )
          : await jobs.installClaudeAcpAdapter(
              title: title,
              onSucceeded: onSucceeded,
            );
      if (!mounted) return;
      AppToast.show(
        context,
        message: result.message,
        variant: result.success ? TpToastVariant.success : TpToastVariant.error,
      );
    } catch (error) {
      if (!mounted) return;
      AppToast.show(
        context,
        message: error.toString(),
        variant: TpToastVariant.error,
      );
    } finally {
      if (mounted) setState(() {});
    }
  }

  String _adapterInstallLabel(AppLocalizations l10n) {
    final installer = _settings?.adapterInstaller;
    if (installer is CodexAcpAdapterInstaller) {
      return l10n.codexAcpAdapterInstallButton;
    }
    return l10n.claudeAcpAdapterInstallButton;
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SessionPreferencesCubit, SessionPreferencesState>(
      bloc: widget.cubit,
      builder: (context, _) => _buildCard(context),
    );
  }

  Widget _buildCard(BuildContext context) {
    final l10n = context.l10n;
    final styles = TpTextStyles.of(context);
    final exec = _executable;
    if (exec == null) return const SizedBox.shrink();

    final spec = exec.executablePathRowSpec;
    final cubit = widget.cubit;
    final cliKnown = cubit.hasKnownCliExecutable(widget.cli);
    final adapterKnown = cubit.hasKnownAcpAdapter(widget.cli);
    final cliUpdate =
        _npmInstaller(exec) != null &&
        isNpmUpdate(
          installed: cubit.installedVersion(widget.cli, CliBinaryKind.cli),
          latest: cubit.latestVersion(widget.cli, CliBinaryKind.cli),
        );
    final adapterUpdate =
        _separateAdapter &&
        isNpmUpdate(
          installed: cubit.installedVersion(widget.cli, CliBinaryKind.adapter),
          latest: cubit.latestVersion(widget.cli, CliBinaryKind.adapter),
        );
    final kind = readinessChip(
      cliKnown: cliKnown,
      needsAdapter: _separateAdapter,
      adapterKnown: adapterKnown,
      cliUpdate: cliUpdate,
      adapterUpdate: adapterUpdate,
    );
    final chipLabel = switch (kind) {
      CliReadinessChipKind.ready => l10n.cliReadinessReady,
      CliReadinessChipKind.updateAvailable => l10n.cliReadinessUpdateAvailable,
      CliReadinessChipKind.needsSetup => l10n.cliReadinessNeedsSetup,
    };
    final userPath = cubit.configuredExecutablePath(widget.cli).trim();
    final cliPath = userPath.isNotEmpty
        ? userPath
        : cubit.resolveExecutable(widget.cli);
    final cliVersion =
        cubit.installedVersion(widget.cli, CliBinaryKind.cli) ??
        l10n.cliReadinessVersionUnknown;
    final jobs = context.read<InstallJobRegistry>();
    final installingCli = jobs.isRunning(_cliJobKey(context));
    final installingAdapter = jobs.isRunning(_adapterJobKey());
    final isRemote = context.select<ConnectionModeService, bool>(
      (service) => service.isRemoteWorkPlane,
    );
    final busyCli = _locatingCli || installingCli;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              CliBrandIcon(
                cli: widget.cli,
                label: exec.label(l10n),
                size: 28,
                borderRadius: 7,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(exec.label(l10n), style: styles.mdSemibold),
              ),
              TpStatusBadge(
                label: chipLabel,
                tone: kind == CliReadinessChipKind.ready
                    ? TpStatusBadgeTone.success
                    : TpStatusBadgeTone.warning,
              ),
            ],
          ),
          const SizedBox(height: 12),
          _ResourceRow(
            label: l10n.cliReadinessRowCli,
            pathKey: Key(spec.fieldKey),
            path: cliPath,
            version: cliVersion,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              if (!cliKnown && exec.supportsInstaller)
                _ActionButton(
                  buttonKey: Key(spec.installKey),
                  icon: installingCli
                      ? _spinner
                      : Icon(
                          Icons.download_outlined,
                          size: context.tpIconSizes.md,
                        ),
                  label: installingCli
                      ? l10n.cliInstallInstalling
                      : l10n.cliInstallButton,
                  onPressed: busyCli
                      ? null
                      : () => _installOrUpgradeCli(upgrading: false),
                ),
              if (cliUpdate)
                _ActionButton(
                  buttonKey: AppKeys.cliUpgradeButtonFor(widget.cli),
                  icon: installingCli
                      ? _spinner
                      : Icon(
                          Icons.upgrade_outlined,
                          size: context.tpIconSizes.md,
                        ),
                  label: installingCli
                      ? l10n.cliInstallUpgrading
                      : l10n.cliUpgradeButton,
                  onPressed: busyCli
                      ? null
                      : () => _installOrUpgradeCli(upgrading: true),
                ),
              _ActionButton(
                buttonKey: Key(spec.browseKey),
                icon: Icon(
                  Icons.folder_open_outlined,
                  size: context.tpIconSizes.md,
                ),
                label: l10n.cliExecutablePathBrowse,
                onPressed: (isRemote || busyCli) ? null : _pickFile,
              ),
              TextButton(
                key: Key(spec.resetKey),
                onPressed: busyCli
                    ? null
                    : (userPath.isEmpty ? _locateCli : _resetCliPath),
                child: _locatingCli
                    ? _spinner
                    : Text(
                        userPath.isEmpty
                            ? l10n.cliExecutablePathLocate
                            : l10n.cliExecutablePathReset,
                      ),
              ),
            ],
          ),
          if (_hasAcp) ...[
            const SizedBox(height: 12),
            _buildAcpBlock(
              context,
              l10n: l10n,
              adapterKnown: adapterKnown,
              adapterUpdate: adapterUpdate,
              installingAdapter: installingAdapter,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAcpBlock(
    BuildContext context, {
    required AppLocalizations l10n,
    required bool adapterKnown,
    required bool adapterUpdate,
    required bool installingAdapter,
  }) {
    final cubit = widget.cubit;
    final adapterPath = cubit.discoveredAcpAdapterPath(widget.cli);
    final adapterVersion =
        cubit.installedVersion(widget.cli, CliBinaryKind.adapter) ??
        l10n.cliReadinessVersionUnknown;
    final showSwitch = _settings?.showsPersonalAcpSwitch == true;
    final hideAdapterActions = _isAndroid;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_separateAdapter) ...[
          _ResourceRow(
            label: l10n.cliReadinessRowAcp,
            path: adapterKnown ? adapterPath : l10n.cliReadinessAdapterMissing,
            version: adapterKnown
                ? adapterVersion
                : l10n.cliReadinessVersionUnknown,
          ),
          if (!hideAdapterActions) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                if (!adapterKnown && _settings?.adapterInstaller != null)
                  _ActionButton(
                    buttonKey: AppKeys.acpAdapterInstallButtonFor(widget.cli),
                    icon: installingAdapter
                        ? _spinner
                        : Icon(
                            Icons.download_outlined,
                            size: context.tpIconSizes.md,
                          ),
                    label: installingAdapter
                        ? l10n.cliInstallInstalling
                        : _adapterInstallLabel(l10n),
                    onPressed: (_locatingAdapter || installingAdapter)
                        ? null
                        : () => _installOrUpgradeAdapter(upgrading: false),
                  ),
                _ActionButton(
                  buttonKey: AppKeys.acpAdapterLocateButtonFor(widget.cli),
                  icon: _locatingAdapter
                      ? _spinner
                      : Icon(Icons.search, size: context.tpIconSizes.md),
                  label: l10n.cliExecutablePathLocate,
                  onPressed: (_locatingAdapter || installingAdapter)
                      ? null
                      : _locateAdapter,
                ),
                if (adapterUpdate)
                  _ActionButton(
                    buttonKey: AppKeys.acpAdapterUpgradeButtonFor(widget.cli),
                    icon: installingAdapter
                        ? _spinner
                        : Icon(
                            Icons.upgrade_outlined,
                            size: context.tpIconSizes.md,
                          ),
                    label: installingAdapter
                        ? l10n.cliInstallUpgrading
                        : l10n.cliUpgradeButton,
                    onPressed: (_locatingAdapter || installingAdapter)
                        ? null
                        : () => _installOrUpgradeAdapter(upgrading: true),
                  ),
              ],
            ),
          ],
        ] else
          _ResourceRow(
            label: l10n.cliReadinessRowAcp,
            path: l10n.cliReadinessUsesCli,
            version: l10n.cliReadinessVersionUnknown,
          ),
        if (showSwitch)
          SwitchListTile(
            key: AppKeys.personalAcpSwitchFor(widget.cli),
            contentPadding: EdgeInsets.zero,
            title: Text(
              _isAndroid
                  ? l10n.claudePersonalAcpAndroidDisabled
                  : l10n.personalAcpSwitchLabel,
            ),
            subtitle: _isAndroid
                ? null
                : Text(l10n.personalAcpSwitchCaption),
            value: !_isAndroid && cubit.personalAcpDefaultFor(widget.cli),
            onChanged: _isAndroid
                ? null
                : (value) => cubit.setPersonalAcpDefaultFor(widget.cli, value),
          ),
      ],
    );
  }
}

class _ResourceRow extends StatelessWidget {
  const _ResourceRow({
    required this.label,
    required this.path,
    required this.version,
    this.pathKey,
  });

  final String label;
  final String path;
  final String version;
  final Key? pathKey;

  @override
  Widget build(BuildContext context) {
    final styles = TpTextStyles.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 40,
          child: Text(label, style: styles.mutedSm),
        ),
        Expanded(
          child: Text(
            path,
            key: pathKey,
            style: appMonoTextStyle(context),
          ),
        ),
        Text(version, style: styles.mutedSm),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.buttonKey,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final Key buttonKey;
  final Widget icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      key: buttonKey,
      onPressed: onPressed,
      icon: icon,
      label: Text(label),
    );
  }
}

const _spinner = SizedBox(
  width: 16,
  height: 16,
  child: CircularProgressIndicator(strokeWidth: 2),
);

SshProfile? _remoteSshProfile(
  BuildContext context,
  ConnectionModeService mode,
) {
  if (!mode.isRemoteWorkPlane) return null;
  if (mode.isTermuxMode) {
    final config = context.read<TermuxCubit>().state.config;
    return config == null ? null : termuxTransportProfile(config);
  }
  return context.read<SshProfileCubit>().state.selectedProfile;
}
