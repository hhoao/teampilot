import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:teampilot/theme/app_icon_sizes.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/session_preferences_cubit.dart';
import '../../cubits/ssh_profile_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/team_config.dart';
import '../../services/app/connection_mode_service.dart';
import '../../services/cli/cli_installer_service.dart';
import '../../services/ssh/ssh_client_factory.dart';
import '../../utils/debounce/debounce.dart';
import '../../widgets/cli_install_progress_panel.dart';
import '../../widgets/settings/workspace_settings_widgets.dart';
import 'session_config_constants.dart';

class CliExecutablePathSettingsRow extends StatefulWidget {
  const CliExecutablePathSettingsRow({
    required this.cubit,
    required this.cli,
    required this.title,
    required this.subtitle,
    required this.fieldKey,
    required this.browseKey,
    required this.resetKey,
    required this.debouncerTag,
    required this.showDividerBelow,
    this.installKey,
  });

  final SessionPreferencesCubit cubit;
  final CliTool cli;
  final String title;
  final String subtitle;
  final Key fieldKey;
  final Key browseKey;
  final Key resetKey;
  final String debouncerTag;
  final bool showDividerBelow;
  final Key? installKey;

  @override
  State<CliExecutablePathSettingsRow> createState() =>
      CliExecutablePathSettingsRowState();
}

class CliExecutablePathSettingsRowState
    extends State<CliExecutablePathSettingsRow> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  late final Debouncer _persistDebouncer;
  String _lastSyncedPath = '';
  bool _isInstalling = false;
  CliInstallPhase? _installPhase;
  final List<String> _installLog = [];

  @override
  void initState() {
    super.initState();
    _persistDebouncer = Debouncer(
      tag: widget.debouncerTag,
      duration: kSessionPathPersistDebounce,
    );
    _focusNode = FocusNode()..addListener(_onFocusChanged);
    final initial = _storedPath();
    _controller = TextEditingController(text: initial);
    _lastSyncedPath = initial;
  }

  @override
  void dispose() {
    _persistDebouncer.dispose();
    _focusNode.removeListener(_onFocusChanged);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  String _storedPath() =>
      widget.cubit.state.preferences.cliExecutablePathFor(widget.cli.value);

  void _syncFromState(String stored) {
    if (stored == _lastSyncedPath) return;
    _persistDebouncer.cancel();
    _lastSyncedPath = stored;
    _controller.value = TextEditingValue(
      text: stored,
      selection: TextSelection.collapsed(offset: stored.length),
    );
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.any);
    final picked = result?.files.single.path;
    if (picked == null) return;
    if (!mounted) return;
    _persistDebouncer.cancel();
    _controller.text = picked;
    await widget.cubit.setCliExecutablePathFor(widget.cli, picked);
  }

  Future<void> _persistFromField() async {
    if (!mounted) return;
    final trimmed = _controller.text.trim();
    final stored = _storedPath().trim();
    if (trimmed == stored) return;
    await widget.cubit.setCliExecutablePathFor(widget.cli, _controller.text);
  }

  void _onFocusChanged() {
    if (!mounted) return;
    if (!_focusNode.hasFocus) {
      _flushPersist();
    }
  }

  void _scheduleDebouncedPersist() {
    _persistDebouncer(() {
      if (mounted) {
        _persistFromField();
      }
    });
  }

  void _flushPersist() {
    if (!mounted) return;
    _persistDebouncer.cancel();
    _persistFromField();
  }

  Future<void> _reset() async {
    _persistDebouncer.cancel();
    _controller.clear();
    await widget.cubit.setCliExecutablePathFor(widget.cli, '');
  }

  Future<void> _installCli() async {
    if (_isInstalling) return;
    setState(() {
      _isInstalling = true;
      _installPhase = CliInstallPhase.checkingNpm;
      _installLog.clear();
    });
    try {
      final connectionMode = context.read<ConnectionModeService>();
      final sshProfile = context.read<SshProfileCubit>().state.selectedProfile;
      final installer = CliInstallerService(
        sshClientFactory: context.read<SshClientFactory>(),
      );
      final result = await installer.install(
        cli: widget.cli,
        mode: connectionMode.isSshMode
            ? CliInstallMode.ssh
            : CliInstallMode.local,
        sshProfile: sshProfile,
        onProgress: _onInstallProgress,
      );
      if (!mounted) return;
      final path = result.executablePath?.trim() ?? '';
      if (result.success && path.isNotEmpty) {
        _persistDebouncer.cancel();
        _controller.text = path;
        await widget.cubit.setCliExecutablePathFor(widget.cli, path);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(result.message)));
    } finally {
      if (mounted) {
        setState(() {
          _isInstalling = false;
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
    final stored = _storedPath();
    _syncFromState(stored);

    final isSshMode = widget.cubit.isSshMode;
    final effective = widget.cubit.resolveExecutable(widget.cli);
    final isFallback = stored.trim().isEmpty;
    final fieldEmpty = _controller.text.trim().isEmpty;
    final hint = fieldEmpty ? '${l10n.cliExecutablePathUsing}$effective' : null;

    return SettingsLabeledStackedRow(
      title: widget.title,
      subtitle: widget.subtitle,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: TextField(
                  key: widget.fieldKey,
                  controller: _controller,
                  focusNode: _focusNode,
                  decoration: InputDecoration(
                    hintText: hint,
                    hintMaxLines: 1,
                    floatingLabelBehavior: FloatingLabelBehavior.never,
                  ),
                  onChanged: (_) => _scheduleDebouncedPersist(),
                  onSubmitted: (_) => _flushPersist(),
                ),
              ),
              const SizedBox(width: 6),
              if (widget.installKey != null) ...[
                OutlinedButton.icon(
                  key: widget.installKey,
                  onPressed: _isInstalling ? null : _installCli,
                  icon: _isInstalling
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.download_outlined, size: AppIconSizes.md),
                  label: Text(
                    _isInstalling
                        ? l10n.cliInstallInstalling
                        : l10n.cliInstallButton,
                  ),
                ),
                const SizedBox(width: 6),
              ],
              OutlinedButton.icon(
                key: widget.browseKey,
                onPressed: isSshMode ? null : _pickFile,
                icon: const Icon(Icons.folder_open_outlined, size: AppIconSizes.md),
                label: Text(l10n.cliExecutablePathBrowse),
              ),
              const SizedBox(width: 6),
              TextButton(
                key: widget.resetKey,
                onPressed: isFallback ? null : _reset,
                child: Text(l10n.cliExecutablePathReset),
              ),
            ],
          ),
          if (_isInstalling && _installPhase != null) ...[
            const SizedBox(height: 12),
            CliInstallProgressPanel(
              phase: _installPhase!,
              logLines: _installLog,
            ),
          ],
        ],
      ),
      showDividerBelow: widget.showDividerBelow,
    );
  }
}
