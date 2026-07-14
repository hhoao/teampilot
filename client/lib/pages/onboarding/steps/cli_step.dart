import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:teampilot/theme/app_icon_sizes.dart';
import 'package:teampilot/theme/app_toast_theme.dart';
import 'package:teampilot/widgets/app_toast/app_toast.dart';

import '../../../cubits/session_preferences_cubit.dart';
import '../../../cubits/ssh_profile_cubit.dart';
import '../../../l10n/l10n_extensions.dart';
import '../../../models/ssh_profile.dart';
import '../../../models/team_config.dart';
import '../../../services/app/connection_mode_service.dart';
import '../../../services/cli/cli_executable_discovery.dart';
import '../../../services/cli/cli_installer_service.dart';
import '../../../services/cli/remote_cli_locator.dart';
import '../../../services/cli/registry/capabilities/installer_capability.dart';
import '../../../services/cli/registry/cli_display_name.dart';
import '../../../services/cli/registry/cli_tool_definition.dart';
import '../../../services/cli/registry/cli_tool_registry.dart';
import '../../../services/cli/registry/cli_tool_registry_scope.dart';
import '../../../services/ssh/ssh_client_factory.dart';
import '../../../theme/app_text_styles.dart';
import '../../../widgets/cli_install_progress_panel.dart';
import '../../../widgets/settings/workspace_settings_widgets.dart';
import 'onboarding_cli_row.dart';

class OnboardingCliStep extends StatefulWidget {
  const OnboardingCliStep({super.key, this.isActive = true});

  final bool isActive;

  @override
  State<OnboardingCliStep> createState() => _OnboardingCliStepState();
}

class _OnboardingCliStepState extends State<OnboardingCliStep> {
  final _controllers = <CliTool, TextEditingController>{};
  final _persistDebouncers = <CliTool, Timer>{};
  final _detectedPaths = <CliTool, String?>{};
  var _detecting = false;
  var _hasStartedDetect = false;
  CliTool? _installingCli;
  CliInstallPhase? _installPhase;
  final List<String> _installLog = [];
  String? _detectError;

  @override
  void initState() {
    super.initState();
    if (widget.isActive) {
      _startDetectIfNeeded();
    }
  }

  @override
  void didUpdateWidget(OnboardingCliStep oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) {
      _startDetectIfNeeded();
    }
  }

  void _startDetectIfNeeded() {
    if (_hasStartedDetect) return;
    _hasStartedDetect = true;
    unawaited(_detect());
  }

  @override
  void dispose() {
    for (final timer in _persistDebouncers.values) {
      timer.cancel();
    }
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  CliToolRegistry get _registry =>
      CliToolRegistryScope.maybeOf(context) ?? CliToolRegistry.builtIn();

  List<CliToolDefinition> get _launchable => _registry.launchable.toList();

  TextEditingController _controllerFor(CliTool cli) =>
      _controllers.putIfAbsent(cli, TextEditingController.new);

  bool _supportsInstall(CliTool cli) =>
      _registry.capability<InstallerCapability>(cli)?.supportsInstaller ?? false;

  Future<void> _detect() async {
    setState(() {
      _detecting = true;
      _detectError = null;
    });
    try {
      final mode = context.read<ConnectionModeService>();
      final discovery = CliExecutableDiscovery(registry: _registry);
      final Map<CliTool, String> located;
      if (mode.isSshMode) {
        final profile = context.read<SshProfileCubit>().state.selectedProfile;
        if (profile == null) {
          located = const {};
        } else {
          located = await _locateRemoteAll(
            profile,
            context.read<SshClientFactory>(),
            discovery,
          );
        }
      } else {
        located = await discovery.locateLocal();
      }
      if (!mounted) return;

      final prefs = context.read<SessionPreferencesCubit>();
      for (final def in _launchable) {
        final cli = def.id;
        final path = located[cli]?.trim() ?? '';
        _controllerFor(cli).text = path;
        _detectedPaths[cli] = path.isEmpty ? null : path;
        await prefs.setCliExecutablePathFor(cli, path);
      }
      if (!mounted) return;
      setState(() => _detecting = false);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _detectError = error.toString();
        _detecting = false;
      });
    }
  }

  Future<void> _persistPath(CliTool cli, String value) {
    return context.read<SessionPreferencesCubit>().setCliExecutablePathFor(
      cli,
      value,
    );
  }

  Future<void> _install(CliTool cli) async {
    if (_installingCli != null || !_supportsInstall(cli)) return;
    setState(() {
      _installingCli = cli;
      _installPhase = CliInstallPhase.checkingNpm;
      _installLog.clear();
    });
    try {
      final connectionMode = context.read<ConnectionModeService>();
      final sshProfile = context.read<SshProfileCubit>().state.selectedProfile;
      final installer = CliInstallerService(
        sshClientFactory: context.read<SshClientFactory>(),
        cliToolRegistry: _registry,
      );
      final result = await installer.install(
        cli: cli,
        mode: connectionMode.isSshMode
            ? CliInstallMode.ssh
            : CliInstallMode.local,
        sshProfile: sshProfile,
        onProgress: _onInstallProgress,
      );
      if (!mounted) return;
      final path = result.executablePath?.trim() ?? '';
      if (result.success && path.isNotEmpty) {
        setState(() {
          _controllerFor(cli).text = path;
          _detectedPaths[cli] = path;
          _detectError = null;
        });
        await _persistPath(cli, path);
      } else if (result.success) {
        await _detect();
      }
      if (!mounted) return;
      AppToast.show(
        context,
        message: result.message,
        variant: result.success
            ? AppToastVariant.success
            : AppToastVariant.error,
      );
    } finally {
      if (mounted) {
        setState(() {
          _installingCli = null;
          _installPhase = null;
        });
      }
    }
  }

  void _onInstallProgress(CliInstallProgress progress) {
    if (!mounted) return;
    setState(() {
      _installPhase = progress.phase;
      final detail = progress.detail?.trim();
      if (detail != null && detail.isNotEmpty) {
        _installLog.add(detail);
        if (_installLog.length > 80) {
          _installLog.removeRange(0, _installLog.length - 80);
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final launchable = _launchable;
    final busy = _detecting || _installingCli != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.onboardingCliTitle,
          style: AppTextStyles.of(context).display,
        ),
        const SizedBox(height: 8),
        Text(
          l10n.onboardingCliSubtitle,
          style: AppTextStyles.of(context).mutedMd,
        ),
        if (_detectError != null) ...[
          const SizedBox(height: 12),
          Text(
            _detectError!,
            style: AppTextStyles.of(context).mutedMd.copyWith(
              color: Theme.of(context).colorScheme.error,
            ),
          ),
        ],
        const SizedBox(height: 20),
        SettingsSurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < launchable.length; i++) ...[
                OnboardingCliRow(
                  definition: launchable[i],
                  label: cliDisplayName(launchable[i], l10n),
                  controller: _controllerFor(launchable[i].id),
                  detectedPath: _detectedPaths[launchable[i].id],
                  detecting: _detecting,
                  supportsInstall: _supportsInstall(launchable[i].id),
                  installing: _installingCli == launchable[i].id,
                  installEnabled: !busy,
                  onPathChanged: (value) {
                    setState(() {
                      _detectError = null;
                      final trimmed = value.trim();
                      _detectedPaths[launchable[i].id] =
                          trimmed.isEmpty ? null : trimmed;
                    });
                    _persistDebouncers[launchable[i].id]?.cancel();
                    _persistDebouncers[launchable[i].id] = Timer(
                      const Duration(milliseconds: 300),
                      () => unawaited(_persistPath(launchable[i].id, value)),
                    );
                  },
                  onInstall: () => unawaited(_install(launchable[i].id)),
                ),
                if (i < launchable.length - 1) const Divider(height: 1),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: busy ? null : _detect,
            icon: Icon(Icons.refresh, size: context.appIconSizes.md),
            label: Text(l10n.onboardingCliRedetect),
          ),
        ),
        if (_installingCli != null && _installPhase != null) ...[
          const SizedBox(height: 12),
          CliInstallProgressPanel(phase: _installPhase!, logLines: _installLog),
        ],
      ],
    );
  }
}

Future<Map<CliTool, String>> _locateRemoteAll(
  SshProfile profile,
  SshClientFactory clientFactory,
  CliExecutableDiscovery discovery,
) async {
  final client = await clientFactory.clientForStorage(profile);
  return discovery.locateRemote(
    run: RemoteCliLocator.runnerForClient(client),
  );
}
