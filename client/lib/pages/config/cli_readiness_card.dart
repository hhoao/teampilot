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
import '../../services/cli/registry/capabilities/acp_settings_capability.dart';
import '../../services/cli/registry/cli_tool_registry.dart';
import '../../services/cli/registry/installer/npm_installer_capability.dart';
import '../../services/install/install_job_enqueue.dart';
import '../../services/install/install_job_keys.dart';
import '../../services/install/install_job_registry.dart';
import '../../services/install/install_job_scope_resolver.dart';
import '../../services/ssh/ssh_client_factory.dart';
import '../../services/termux/termux_transport_profile.dart';
import '../../utils/ui/app_keys.dart';
import '../../widgets/app_toast/app_toast.dart';
import '../../widgets/cli/cli_brand_icon.dart';
import 'cli_readiness_path_row.dart';

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
  final installedToken = cliVersionToken(installed) ?? installed.trim();
  final latestToken = cliVersionToken(latest) ?? latest.trim();
  return installedToken != latestToken;
}

String displayCliVersion(String? installed, String unknown) {
  if (installed == null || installed.trim().isEmpty) return unknown;
  return cliVersionToken(installed) ?? installed;
}

class CliReadinessCard extends StatefulWidget {
  const CliReadinessCard({
    required this.cli,
    required this.cubit,
    this.isAndroidOverride,
    this.versionProbe,
    this.locateOverride,
    super.key,
  });

  final CliTool cli;
  final SessionPreferencesCubit cubit;
  final bool? isAndroidOverride;
  final CliVersionProbe? versionProbe;

  /// Test seam to avoid spawning discovery subprocesses.
  final Future<String?> Function()? locateOverride;

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

  Future<void> _pickAdapterFile() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.any);
    final picked = result?.files.single.path;
    if (picked == null || !mounted) return;
    await widget.cubit.setAcpAdapterPathFor(widget.cli, picked);
    await _probeInstalled(CliBinaryKind.adapter, picked);
  }

  Future<void> _resetCliPath() async {
    await widget.cubit.setCliExecutablePathFor(widget.cli, '');
  }

  Future<void> _resetAdapterPath() async {
    await widget.cubit.setAcpAdapterPathFor(widget.cli, '');
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
    if (widget.locateOverride != null) return widget.locateOverride!();
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
      final found = await AcpAdapterDiscovery(
        registry: _registry,
      ).locateLocal();
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
      await widget.cubit.setAcpAdapterPathFor(widget.cli, path);
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
        await widget.cubit.setAcpAdapterPathFor(widget.cli, path);
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
    final cliVersion = displayCliVersion(
      cubit.installedVersion(widget.cli, CliBinaryKind.cli),
      l10n.cliReadinessVersionUnknown,
    );
    final jobs = context.read<InstallJobRegistry>();
    final installingCli = jobs.isRunning(_cliJobKey(context));
    final installingAdapter = jobs.isRunning(_adapterJobKey());
    final isRemote = context.select<ConnectionModeService, bool>(
      (service) => service.isRemoteWorkPlane,
    );
    final busyCli = _locatingCli || installingCli;
    final showCliInstall = !cliKnown && exec.supportsInstaller;

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
              Expanded(child: Text(exec.label(l10n), style: styles.mdSemibold)),
              TpStatusBadge(
                label: chipLabel,
                tone: kind == CliReadinessChipKind.ready
                    ? TpStatusBadgeTone.success
                    : TpStatusBadgeTone.warning,
              ),
            ],
          ),
          const SizedBox(height: 12),
          CliReadinessPathRow(
            label: l10n.cliReadinessRowCli,
            fieldKey: Key(spec.fieldKey),
            storedPath: userPath,
            discoveredPath: cubit.discoveredExecutablePath(widget.cli),
            version: cliVersion,
            onPersist: (value) =>
                cubit.setCliExecutablePathFor(widget.cli, value),
            browseKey: Key(spec.browseKey),
            onBrowse: (isRemote || busyCli) ? null : _pickFile,
            locateOrResetKey: Key(spec.resetKey),
            locateLabel: l10n.cliExecutablePathLocate,
            resetLabel: l10n.cliExecutablePathReset,
            onLocateOrReset: busyCli
                ? null
                : (userPath.isEmpty ? _locateCli : _resetCliPath),
            installKey: showCliInstall ? Key(spec.installKey) : null,
            onInstall: showCliInstall
                ? () => _installOrUpgradeCli(upgrading: false)
                : null,
            installing: installingCli,
            upgradeKey: cliUpdate
                ? AppKeys.cliUpgradeButtonFor(widget.cli)
                : null,
            onUpgrade: cliUpdate
                ? () => _installOrUpgradeCli(upgrading: true)
                : null,
            locating: _locatingCli,
          ),
          if (_separateAdapter ||
              _settings?.showsPersonalAcpSwitch == true) ...[
            const SizedBox(height: 12),
            _buildAcpBlock(
              context,
              l10n: l10n,
              adapterKnown: adapterKnown,
              adapterUpdate: adapterUpdate,
              installingAdapter: installingAdapter,
              isRemote: isRemote,
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
    required bool isRemote,
  }) {
    final cubit = widget.cubit;
    final adapterStored = cubit.configuredAcpAdapterPath(widget.cli);
    final adapterVersion = displayCliVersion(
      cubit.installedVersion(widget.cli, CliBinaryKind.adapter),
      l10n.cliReadinessVersionUnknown,
    );
    final showSwitch = _settings?.showsPersonalAcpSwitch == true;
    final busyAdapter = _locatingAdapter || installingAdapter;
    final showAdapterInstall =
        !adapterKnown && _settings?.adapterInstaller != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_separateAdapter)
          CliReadinessPathRow(
            label: l10n.cliReadinessRowAcp,
            fieldKey: AppKeys.acpAdapterPathFieldFor(widget.cli),
            storedPath: adapterStored,
            discoveredPath: cubit.discoveredAcpAdapterPath(widget.cli),
            version: adapterVersion,
            onPersist: (value) => cubit.setAcpAdapterPathFor(widget.cli, value),
            browseKey: AppKeys.acpAdapterBrowseButtonFor(widget.cli),
            onBrowse: (isRemote || busyAdapter) ? null : _pickAdapterFile,
            locateOrResetKey: adapterStored.trim().isEmpty
                ? AppKeys.acpAdapterLocateButtonFor(widget.cli)
                : AppKeys.acpAdapterResetButtonFor(widget.cli),
            locateLabel: l10n.cliExecutablePathLocate,
            resetLabel: l10n.cliExecutablePathReset,
            onLocateOrReset: busyAdapter
                ? null
                : (adapterStored.trim().isEmpty
                      ? _locateAdapter
                      : _resetAdapterPath),
            installKey: showAdapterInstall
                ? AppKeys.acpAdapterInstallButtonFor(widget.cli)
                : null,
            onInstall: showAdapterInstall
                ? () => _installOrUpgradeAdapter(upgrading: false)
                : null,
            installLabel: _adapterInstallLabel(l10n),
            installing: installingAdapter,
            upgradeKey: adapterUpdate
                ? AppKeys.acpAdapterUpgradeButtonFor(widget.cli)
                : null,
            onUpgrade: adapterUpdate
                ? () => _installOrUpgradeAdapter(upgrading: true)
                : null,
            locating: _locatingAdapter,
            enabled: !_isAndroid,
          ),
        if (showSwitch)
          TpPreferenceRow(
            title: _isAndroid
                ? l10n.claudePersonalAcpAndroidDisabled
                : l10n.personalAcpSwitchLabel,
            subtitle: _isAndroid ? null : l10n.personalAcpSwitchCaption,
            padding: EdgeInsets.zero,
            showDividerBelow: false,
            trailing: Switch(
              key: AppKeys.personalAcpSwitchFor(widget.cli),
              value: !_isAndroid && cubit.personalAcpDefaultFor(widget.cli),
              onChanged: _isAndroid
                  ? null
                  : (value) =>
                        cubit.setPersonalAcpDefaultFor(widget.cli, value),
            ),
          ),
      ],
    );
  }
}

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
