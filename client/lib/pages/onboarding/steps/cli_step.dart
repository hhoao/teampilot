import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';
import '../../../widgets/app_toast/app_toast.dart';

import '../../../cubits/progress_activity_cubit.dart';
import '../../../cubits/session_preferences_cubit.dart';
import '../../../cubits/ssh_profile_cubit.dart';
import '../../../cubits/termux_cubit.dart';
import '../../../l10n/l10n_extensions.dart';
import '../../../models/session_preferences.dart';
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
import '../../../services/progress_activity/cli_provision_activity_adapter.dart';
import '../../../services/ssh/ssh_client_factory.dart';
import '../../../services/termux/termux_transport_profile.dart';
import '../../../widgets/cli_install_progress_panel.dart';
import 'onboarding_cli_row.dart';
import 'onboarding_step_scaffold.dart';

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
  final _detecting = ValueNotifier(false);
  final _busy = ValueNotifier(false);
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_detect());
    });
  }

  @override
  void dispose() {
    for (final timer in _persistDebouncers.values) {
      timer.cancel();
    }
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    _detecting.dispose();
    _busy.dispose();
    super.dispose();
  }

  CliToolRegistry get _registry =>
      CliToolRegistryScope.maybeOf(context) ?? CliToolRegistry.builtIn();

  List<CliToolDefinition> get _launchable => _registry.launchable.toList();

  TextEditingController _controllerFor(CliTool cli) =>
      _controllers.putIfAbsent(cli, TextEditingController.new);

  bool _supportsInstall(CliTool cli) =>
      _registry.capability<InstallerCapability>(cli)?.supportsInstaller ?? false;

  void _syncBusy() {
    _busy.value = _detecting.value || _installingCli != null;
  }

  Future<void> _detect() async {
    _detectError = null;
    _detecting.value = true;
    _syncBusy();
    try {
      final prefs = context.read<SessionPreferencesCubit>();
      var seeded = false;
      for (final def in _launchable) {
        final cli = def.id;
        final configured = prefs.configuredExecutablePath(cli).trim();
        final known = configured.isNotEmpty
            ? configured
            : prefs.discoveredExecutablePath(cli);
        if (known.isEmpty) continue;
        _controllerFor(cli).text = known;
        if (_detectedPaths[cli] != known) {
          _detectedPaths[cli] = known;
          seeded = true;
        }
      }
      // Controllers update fields without setState; only refresh status icons.
      if (seeded && mounted) setState(() {});

      final mode = context.read<ConnectionModeService>();
      final discovery = CliExecutableDiscovery(registry: _registry);
      final Map<CliTool, String> located;
      if (mode.isRemoteWorkPlane) {
        final profile = mode.isTermuxMode
            ? _termuxProfile(context)
            : context.read<SshProfileCubit>().state.selectedProfile;
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
        located = await discovery.locateLocal(includeShellFallback: false);
      }
      if (!mounted) return;

      final toPersist = <CliTool, String>{};
      var pathsChanged = false;
      for (final def in _launchable) {
        final cli = def.id;
        final path = located[cli]?.trim() ?? '';
        if (path.isEmpty) continue;
        if (_controllerFor(cli).text != path) {
          _controllerFor(cli).text = path;
        }
        if (_detectedPaths[cli] != path) {
          _detectedPaths[cli] = path;
          pathsChanged = true;
        }
        toPersist[cli] = path;
      }
      prefs.mergeLocatedExecutables(located);
      await prefs.setCliExecutablePaths(toPersist);
      if (!mounted) return;
      _detecting.value = false;
      _syncBusy();
      if (pathsChanged) setState(() {});
    } on Object catch (error) {
      if (!mounted) return;
      _detecting.value = false;
      _syncBusy();
      setState(() => _detectError = error.toString());
    }
  }

  Future<void> _persistPath(CliTool cli, String value) {
    return context.read<SessionPreferencesCubit>().setCliExecutablePathFor(
      cli,
      value,
    );
  }

  Future<void> _install(CliTool cli) async {
    if (_busy.value || !_supportsInstall(cli)) return;
    setState(() {
      _installingCli = cli;
      _installPhase = CliInstallPhase.checkingNpm;
      _installLog.clear();
    });
    _syncBusy();
    try {
      final connectionMode = context.read<ConnectionModeService>();
      final sshProfile = connectionMode.isTermuxMode
          ? _termuxProfile(context)
          : context.read<SshProfileCubit>().state.selectedProfile;
      final installer = CliInstallerService(
        sshClientFactory: context.read<SshClientFactory>(),
        cliToolRegistry: _registry,
        preferredNodePath: () => context
            .read<SessionPreferencesCubit>()
            .toolchainPath(SessionPreferences.toolchainNode),
      );
      final def = _registry.tryGet(cli);
      final cliLabel = def != null
          ? cliDisplayName(def, context.l10n, registry: _registry)
          : cli.value;
      final adapter = CliProvisionActivityAdapter(
        cubit: context.read<ProgressActivityCubit>(),
      );
      final result = await adapter.runTracked(
        title: connectionMode.isRemoteWorkPlane
            ? 'Install $cliLabel on ${sshProfile?.host ?? 'remote host'}'
            : 'Install $cliLabel',
        historyMessageFor: (installResult) => installResult.success
            ? '$cliLabel installed'
            : installResult.message,
        run: (onProgress) async {
          final installResult = await installer.install(
            cli: cli,
            mode: connectionMode.isRemoteWorkPlane
                ? CliInstallMode.ssh
                : CliInstallMode.local,
            sshProfile: sshProfile,
            onProgress: (progress) {
              onProgress(progress);
              _onInstallProgress(progress);
            },
          );
          if (!installResult.success) {
            // Fail the tracked activity; caught below so it is not unhandled.
            throw StateError(installResult.message);
          }
          return installResult;
        },
      );
      if (!mounted) return;
      final path = result.executablePath?.trim() ?? '';
      if (result.success && path.isNotEmpty) {
        _controllerFor(cli).text = path;
        setState(() {
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
            ? TpToastVariant.success
            : TpToastVariant.error,
      );
    } on StateError catch (error) {
      if (!mounted) return;
      setState(() => _detectError = error.message);
      AppToast.show(
        context,
        message: error.message,
        variant: TpToastVariant.error,
      );
    } finally {
      if (mounted) {
        setState(() {
          _installingCli = null;
          _installPhase = null;
        });
        _syncBusy();
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

    return OnboardingStepScaffold(
      title: l10n.onboardingCliTitle,
      subtitle: l10n.onboardingCliSubtitle,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          ValueListenableBuilder<bool>(
            valueListenable: _detecting,
            builder: (context, detecting, _) {
              if (!detecting && _detectError == null) {
                return const SizedBox.shrink();
              }
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_detectError != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          _detectError!,
                          style: TpTextStyles.of(context).mutedMd.copyWith(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    if (detecting)
                      Row(
                        children: [
                          SizedBox(
                            width: context.tpIconSizes.md,
                            height: context.tpIconSizes.md,
                            child: const CircularProgressIndicator(
                              strokeWidth: 2,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              l10n.onboardingCliScanning,
                              style: TpTextStyles.of(context).mutedMd,
                            ),
                          ),
                        ],
                      ),
                    if (detecting) ...[
                      const SizedBox(height: 8),
                      const LinearProgressIndicator(minHeight: 2),
                    ],
                  ],
                ),
              );
            },
          ),
          TpCard.outlined(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < launchable.length; i++) ...[
                  OnboardingCliRow(
                    definition: launchable[i],
                    label: cliDisplayName(launchable[i], l10n),
                    controller: _controllerFor(launchable[i].id),
                    detectedPath: _detectedPaths[launchable[i].id],
                    supportsInstall: _supportsInstall(launchable[i].id),
                    installing: _installingCli == launchable[i].id,
                    busyListenable: _busy,
                    onPathChanged: (value) {
                      final trimmed = value.trim();
                      final next = trimmed.isEmpty ? null : trimmed;
                      if (_detectedPaths[launchable[i].id] != next) {
                        setState(() {
                          _detectError = null;
                          _detectedPaths[launchable[i].id] = next;
                        });
                      } else if (_detectError != null) {
                        setState(() => _detectError = null);
                      }
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
            child: ValueListenableBuilder<bool>(
              valueListenable: _busy,
              builder: (context, busy, _) {
                return OutlinedButton.icon(
                  onPressed: busy ? null : _detect,
                  icon: Icon(Icons.refresh, size: context.tpIconSizes.md),
                  label: Text(l10n.onboardingCliRedetect),
                );
              },
            ),
          ),
          if (_installingCli != null && _installPhase != null) ...[
            const SizedBox(height: 12),
            CliInstallProgressPanel(
              phase: _installPhase!,
              logLines: _installLog,
            ),
          ],
        ],
      ),
    );
  }
}

SshProfile? _termuxProfile(BuildContext context) {
  final config = context.read<TermuxCubit>().state.config;
  return config == null ? null : termuxTransportProfile(config);
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
