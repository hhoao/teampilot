import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:teampilot/theme/app_icon_sizes.dart';
import 'package:teampilot/theme/app_toast_theme.dart';
import 'package:teampilot/widgets/app_toast/app_toast.dart';

import '../../cubits/session_preferences_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/session_preferences.dart';
import '../../services/cli/cli_installer_service.dart';
import '../../services/cli/git_installer.dart';
import '../../utils/debounce/debounce.dart';
import '../../widgets/cli_install_progress_panel.dart';
import '../../widgets/settings/workspace_settings_widgets.dart';
import 'session_config_constants.dart';

/// A settings row for a toolchain executable path (git, node, etc.).
///
/// Provides a [TextField] with Browse / Reset / Install actions, plus an
/// inline install-progress panel.  The persisted value is stored via
/// [SessionPreferencesCubit.toolchainPath] / [SessionPreferencesCubit.setToolchainPath].
class ToolchainPathSettingsRow extends StatefulWidget {
  const ToolchainPathSettingsRow({
    super.key,
    required this.cubit,
    required this.toolId,
    required this.title,
    required this.subtitle,
    required this.fallbackExecutable,
    this.fieldKey,
    this.browseKey,
    this.resetKey,
    this.installKey,
    required this.debouncerTag,
    required this.showDividerBelow,
    this.leadingIcon = Icons.build_outlined,
  });

  final SessionPreferencesCubit cubit;

  /// Key used to persist the path in [SessionPreferences.toolchainPaths].
  /// Use [SessionPreferences.toolchainGit] or [SessionPreferences.toolchainNode].
  final String toolId;

  final String title;
  final String subtitle;

  /// Bare command name resolved when no user path is configured.
  final String fallbackExecutable;

  final Key? fieldKey;
  final Key? browseKey;
  final Key? resetKey;
  final Key? installKey;
  final String debouncerTag;
  final bool showDividerBelow;

  /// Icon shown in the title leading position.
  final IconData leadingIcon;

  @override
  State<ToolchainPathSettingsRow> createState() =>
      _ToolchainPathSettingsRowState();
}

class _ToolchainPathSettingsRowState extends State<ToolchainPathSettingsRow> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  late final Debouncer _persistDebouncer;
  String _lastSyncedPath = '';
  bool _isInstalling = false;
  GitInstallPhase? _installPhase;
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

  // ---- data access ----------------------------------------------------------

  String _storedPath() => widget.cubit.toolchainPath(widget.toolId);

  String _resolved() =>
      widget.cubit.resolveToolchainExecutable(
        widget.toolId,
        widget.fallbackExecutable,
      );

  void _syncFromState(String stored) {
    if (stored == _lastSyncedPath) return;
    _persistDebouncer.cancel();
    _lastSyncedPath = stored;
    _controller.value = TextEditingValue(
      text: stored,
      selection: TextSelection.collapsed(offset: stored.length),
    );
  }

  // ---- file picker ----------------------------------------------------------

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.any);
    final picked = result?.files.single.path;
    if (picked == null) return;
    if (!mounted) return;
    _persistDebouncer.cancel();
    _controller.text = picked;
    await widget.cubit.setToolchainPath(widget.toolId, picked);
  }

  // ---- persistence ----------------------------------------------------------

  Future<void> _persistFromField() async {
    if (!mounted) return;
    final trimmed = _controller.text.trim();
    final stored = _storedPath().trim();
    if (trimmed == stored) return;
    await widget.cubit.setToolchainPath(widget.toolId, _controller.text);
  }

  void _onFocusChanged() {
    if (!mounted) return;
    if (!_focusNode.hasFocus) {
      _flushPersist();
    }
  }

  void _scheduleDebouncedPersist() {
    _persistDebouncer(() {
      if (mounted) _persistFromField();
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
    await widget.cubit.setToolchainPath(widget.toolId, '');
  }

  // ---- install --------------------------------------------------------------

  Future<void> _install() async {
    if (_isInstalling) return;
    setState(() {
      _isInstalling = true;
      _installPhase = GitInstallPhase.checking;
      _installLog.clear();
    });

    Future<GitInstallResult> task;
    if (widget.toolId == SessionPreferences.toolchainGit) {
      _addProgressLog('Detecting git...');
      final gitInstaller = const GitInstaller();
      task = gitInstaller.install(
        onProgress: _onInstallProgress,
      );
    } else if (widget.toolId == SessionPreferences.toolchainNode) {
      // Node install is handled by TeampilotNodeInstall in the CLI installer
      // flow. For now, guide the user to the official site.
      setState(() {
        _isInstalling = false;
        _installPhase = null;
      });
      if (!mounted) return;
      AppToast.show(
        context,
        message:
            'Please install Node.js from https://nodejs.org and set the path manually.',
        variant: AppToastVariant.info,
      );
      return;
    } else {
      setState(() {
        _isInstalling = false;
        _installPhase = null;
      });
      return;
    }

    try {
      final result = await task;
      if (!mounted) return;
      final path = result.executablePath?.trim() ?? '';
      if (result.success && path.isNotEmpty) {
        _persistDebouncer.cancel();
        _controller.text = path;
        await widget.cubit.setToolchainPath(widget.toolId, path);
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
          _isInstalling = false;
          _installPhase = null;
        });
      }
    }
  }

  void _onInstallProgress(GitInstallProgress progress) {
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

  void _addProgressLog(String line) {
    if (!mounted) return;
    setState(() {
      _installLog.add(line);
      if (_installLog.length > 80) {
        _installLog.removeRange(0, _installLog.length - 80);
      }
    });
  }

  /// Maps [GitInstallPhase] to [CliInstallPhase] for the shared progress panel.
  static CliInstallPhase _toCliInstallPhase(GitInstallPhase phase) {
    return switch (phase) {
      GitInstallPhase.checking => CliInstallPhase.checkingNpm,
      GitInstallPhase.installing => CliInstallPhase.installingCli,
      GitInstallPhase.locating => CliInstallPhase.locatingExecutable,
    };
  }

  // ---- build ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final stored = _storedPath();
    _syncFromState(stored);

    final effective = _resolved();
    final isFallback = stored.trim().isEmpty;
    final fieldEmpty = _controller.text.trim().isEmpty;
    final hint = fieldEmpty ? '${l10n.cliExecutablePathUsing}$effective' : null;

    return SettingsLabeledStackedRow(
      title: widget.title,
      subtitle: widget.subtitle,
      titleLeading: Icon(widget.leadingIcon, size: 28),
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
                  onPressed: _isInstalling ? null : _install,
                  icon: _isInstalling
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(Icons.download_outlined,
                          size: context.appIconSizes.md),
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
                onPressed: _pickFile,
                icon: Icon(Icons.folder_open_outlined,
                    size: context.appIconSizes.md),
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
              phase: _toCliInstallPhase(_installPhase!),
              logLines: _installLog,
            ),
          ],
        ],
      ),
      showDividerBelow: widget.showDividerBelow,
    );
  }
}
