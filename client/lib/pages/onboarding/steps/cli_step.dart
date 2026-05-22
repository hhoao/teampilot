import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../cubits/session_preferences_cubit.dart';
import '../../../cubits/ssh_profile_cubit.dart';
import '../../../l10n/l10n_extensions.dart';
import '../../../models/ssh_profile.dart';
import '../../../models/team_config.dart';
import '../../../services/cli_installer_service.dart';
import '../../../services/cli_tool_locator.dart';
import '../../../services/connection_mode_service.dart';
import '../../../services/remote_flashskyai_cli_locator.dart';
import '../../../services/ssh_client_factory.dart';
import '../../../utils/app_keys.dart';
import '../../../widgets/app_outline_text_field.dart';
import '../../../widgets/settings/workspace_settings_widgets.dart';

class OnboardingCliStep extends StatefulWidget {
  const OnboardingCliStep({super.key});

  @override
  State<OnboardingCliStep> createState() => _OnboardingCliStepState();
}

class _OnboardingCliStepState extends State<OnboardingCliStep> {
  static const _cli = TeamCli.claude;

  final _controller = TextEditingController();
  var _detecting = false;
  var _installing = false;
  String? _detectedPath;
  String? _detectError;

  @override
  void initState() {
    super.initState();
    _syncFromPreferences();
    unawaited(_detect());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _syncFromPreferences() {
    final cubit = context.read<SessionPreferencesCubit>();
    final stored = cubit.state.preferences.cliExecutablePaths[_cli.value] ?? '';
    if (_controller.text != stored) {
      _controller.text = stored;
    }
  }

  Future<void> _detect() async {
    setState(() {
      _detecting = true;
      _detectError = null;
    });
    try {
      final mode = context.read<ConnectionModeService>();
      String? located;
      if (mode.isSshMode) {
        final profile = context.read<SshProfileCubit>().state.selectedProfile;
        if (profile != null) {
          located = await _locateRemoteClaude(
            profile,
            context.read<SshClientFactory>(),
          );
        }
      } else {
        located = await const CliToolLocator('claude').locate();
      }
      if (!mounted) return;
      setState(() {
        _detectedPath = located;
        _detecting = false;
      });
      if (located != null &&
          located.isNotEmpty &&
          _controller.text.trim().isEmpty) {
        _controller.text = located;
        await context.read<SessionPreferencesCubit>().setCliExecutablePathFor(
          _cli,
          located,
        );
      }
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _detectError = error.toString();
        _detecting = false;
      });
    }
  }

  Future<void> _persistPath(String value) {
    return context.read<SessionPreferencesCubit>().setCliExecutablePathFor(
      _cli,
      value,
    );
  }

  Future<void> _install() async {
    if (_installing) return;
    setState(() => _installing = true);
    try {
      final connectionMode = context.read<ConnectionModeService>();
      final sshProfile = context.read<SshProfileCubit>().state.selectedProfile;
      final installer = CliInstallerService(
        sshClientFactory: context.read<SshClientFactory>(),
      );
      final result = await installer.install(
        cli: _cli,
        mode: connectionMode.isSshMode
            ? CliInstallMode.ssh
            : CliInstallMode.local,
        sshProfile: sshProfile,
      );
      if (!mounted) return;
      final path = result.executablePath?.trim() ?? '';
      if (result.success && path.isNotEmpty) {
        _controller.text = path;
        await _persistPath(path);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.message)),
      );
    } finally {
      if (mounted) setState(() => _installing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final prefsCubit = context.read<SessionPreferencesCubit>();
    final isSshMode = context.read<ConnectionModeService>().isSshMode;
    final effective = prefsCubit.resolveExecutable(_cli);
    final subtitle = isSshMode
        ? l10n.claudeCliExecutablePathDescriptionSsh
        : l10n.claudeCliExecutablePathDescription;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.onboardingCliTitle,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        Text(
          l10n.onboardingCliSubtitle,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 20),
        if (!_detecting)
          if (_detectedPath != null && _detectedPath!.isNotEmpty)
            SettingsSurfaceCard(
              child: ListTile(
                leading: const Icon(Icons.check_circle_outline),
                title: Text(l10n.onboardingCliFound),
                subtitle: Text(
                  _detectedPath!,
                  style: const TextStyle(fontFamily: 'monospace'),
                ),
              ),
            )
          else
            SettingsSurfaceCard(
              child: ListTile(
                leading: Icon(
                  Icons.info_outline,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                title: Text(l10n.onboardingCliNotFound),
                subtitle: _detectError == null ? null : Text(_detectError!),
              ),
            ),
        const SizedBox(height: 16),
        SettingsSurfaceCard(
          child: SettingsLabeledStackedRow(
            title: l10n.claudeCliExecutablePathLabel,
            subtitle: subtitle,
            body: AppOutlineTextField(
              key: AppKeys.claudeCliExecutablePathField,
              controller: _controller,
              hintText: '${l10n.cliExecutablePathUsing}$effective',
              hintMaxLines: 2,
              onChanged: (value) => unawaited(_persistPath(value)),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: _detecting ? null : _detect,
              icon: const Icon(Icons.refresh, size: 16),
              label: Text(l10n.onboardingCliRedetect),
            ),
            OutlinedButton.icon(
              key: AppKeys.claudeCliInstallButton,
              onPressed: _installing ? null : _install,
              icon: _installing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.download_outlined, size: 16),
              label: Text(
                _installing ? l10n.cliInstallInstalling : l10n.cliInstallButton,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

Future<String?> _locateRemoteClaude(
  SshProfile profile,
  SshClientFactory clientFactory,
) async {
  const lookupCommand = 'command -v claude';

  Future<SshCommandResult> runner(String command) async {
    final client = await clientFactory.clientFor(profile);
    final result = await client.runWithResult(command, stderr: false);
    return SshCommandResult(
      exitCode: result.exitCode ?? 1,
      stdout: String.fromCharCodes(result.stdout),
    );
  }

  final direct = await runner(lookupCommand);
  if (direct.exitCode == 0) {
    final parsed = CliToolLocator.parseFirstStdoutLine(direct.stdout);
    if (parsed != null) return parsed;
  }
  for (final shell in const ['bash', 'zsh']) {
    final result = await runner("$shell -ilc '$lookupCommand'");
    if (result.exitCode != 0) continue;
    final parsed = CliToolLocator.parseFirstStdoutLine(result.stdout);
    if (parsed != null) return parsed;
  }
  return null;
}
