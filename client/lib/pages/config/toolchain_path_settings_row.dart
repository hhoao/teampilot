import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';
import '../../widgets/app_toast/app_toast.dart';

import '../../cubits/session_preferences_cubit.dart';
import '../../cubits/ssh_profile_cubit.dart';
import '../../cubits/termux_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/install_job/install_job_key.dart';
import '../../models/session_preferences.dart';
import '../../models/ssh_profile.dart';
import '../../services/app/connection_mode_service.dart';
import '../../services/cli/remote_cli_locator.dart';
import '../../services/cli/toolchain_executable_discovery.dart';
import '../../services/install/install_job_enqueue.dart';
import '../../services/install/install_job_keys.dart';
import '../../services/install/install_job_registry.dart';
import '../../services/install/install_job_scope_resolver.dart';
import '../../services/ssh/ssh_client_factory.dart';
import '../../services/termux/termux_transport_profile.dart';
import '../../utils/debounce/debounce.dart';
import 'session_config_constants.dart';

/// A settings row for a toolchain executable path (git, node, etc.).
///
/// Provides a [TextField] with Browse / Reset / Install actions. The persisted
/// value is stored via [SessionPreferencesCubit.toolchainPath] /
/// [SessionPreferencesCubit.setToolchainPath].
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
    this.locateOverride,
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

  /// Test seam: when non-null, used instead of discovery.
  final Future<String?> Function()? locateOverride;

  @override
  State<ToolchainPathSettingsRow> createState() =>
      _ToolchainPathSettingsRowState();
}

class _ToolchainPathSettingsRowState extends State<ToolchainPathSettingsRow> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  late final Debouncer _persistDebouncer;
  String _lastSyncedPath = '';
  bool _isLocating = false;

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

  String _storedPath() => widget.cubit.toolchainPath(widget.toolId);

  String _resolved() => widget.cubit.resolveToolchainExecutable(
    widget.toolId,
    widget.fallbackExecutable,
  );

  InstallJobKey _installJobKey(BuildContext context) {
    final scope = installJobScopeForContext(context);
    return InstallJobKeys.toolchain(widget.toolId, scope: scope);
  }

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
    await widget.cubit.setToolchainPath(widget.toolId, picked);
  }

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

  Future<void> _locate() async {
    final registry = context.read<InstallJobRegistry>();
    if (_isLocating || registry.isRunning(_installJobKey(context))) return;
    setState(() => _isLocating = true);
    try {
      final path = (await _resolveLocatePath())?.trim() ?? '';
      if (!mounted) return;
      if (path.isEmpty) {
        AppToast.show(
          context,
          message: context.l10n.cliExecutablePathLocateFailed(widget.title),
          variant: TpToastVariant.error,
        );
        return;
      }
      _persistDebouncer.cancel();
      _controller.text = path;
      await widget.cubit.setToolchainPath(widget.toolId, path);
      if (!mounted) return;
      AppToast.show(
        context,
        message: context.l10n.cliExecutablePathLocateSuccess(
          widget.title,
          path,
        ),
        variant: TpToastVariant.success,
      );
    } catch (_) {
      if (!mounted) return;
      AppToast.show(
        context,
        message: context.l10n.cliExecutablePathLocateFailed(widget.title),
        variant: TpToastVariant.error,
      );
    } finally {
      if (mounted) setState(() => _isLocating = false);
    }
  }

  Future<String?> _resolveLocatePath() async {
    if (widget.locateOverride != null) return widget.locateOverride!();
    final connectionMode = context.read<ConnectionModeService>();
    if (connectionMode.isRemoteWorkPlane) {
      final profile = _remoteSshProfile(context, connectionMode);
      if (profile == null) return null;
      final client = await context.read<SshClientFactory>().clientForStorage(
        profile,
      );
      return ToolchainExecutableDiscovery().locateRemoteTool(
        toolId: widget.toolId,
        run: RemoteCliLocator.runnerForClient(client),
      );
    }
    return ToolchainExecutableDiscovery().locateLocalTool(widget.toolId);
  }

  Future<void> _install() async {
    if (widget.toolId == SessionPreferences.toolchainNode) {
      if (!mounted) return;
      AppToast.show(
        context,
        message:
            'Please install Node.js from https://nodejs.org and set the path manually.',
        variant: TpToastVariant.info,
      );
      return;
    }
    if (widget.toolId != SessionPreferences.toolchainGit) return;

    final registry = context.read<InstallJobRegistry>();
    final scope = installJobScopeForContext(context);
    final key = InstallJobKeys.toolchain(widget.toolId, scope: scope);
    if (registry.isRunning(key)) {
      await registry.installToolchain(
        toolId: widget.toolId,
        scope: scope,
        title: context.l10n.cliInstallInstalling,
      );
      return;
    }

    setState(() {});
    try {
      final result = await registry.installToolchain(
        toolId: widget.toolId,
        scope: scope,
        title: context.l10n.cliInstallInstalling,
        onSucceeded: (installResult) async {
          final path = installResult.executablePath?.trim() ?? '';
          if (path.isEmpty) return;
          _persistDebouncer.cancel();
          await widget.cubit.setToolchainPath(widget.toolId, path);
          if (mounted) {
            _controller.text = path;
          }
        },
      );
      if (!mounted) return;
      AppToast.show(
        context,
        message: result.message,
        variant: result.success
            ? TpToastVariant.success
            : TpToastVariant.error,
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

  @override
  Widget build(BuildContext context) {
    return BlocSelector<
      SessionPreferencesCubit,
      SessionPreferencesState,
      (String, int)
    >(
      selector: (state) => (
        state.preferences.toolchainPaths[widget.toolId]?.trim() ?? '',
        state.locatedExecutablesRevision,
      ),
      builder: (context, selected) => _buildRow(context, selected.$1),
    );
  }

  Widget _buildRow(BuildContext context, String stored) {
    final l10n = context.l10n;
    _syncFromState(stored);

    final registry = context.read<InstallJobRegistry>();
    final installKey = _installJobKey(context);
    final isInstalling = registry.isRunning(installKey);

    final effective = _resolved();
    final isFallback = stored.trim().isEmpty;
    final fieldEmpty = _controller.text.trim().isEmpty;
    final hint = fieldEmpty ? '${l10n.cliExecutablePathUsing}$effective' : null;
    final showInstallButton =
        widget.installKey != null &&
        fieldEmpty &&
        !widget.cubit.hasKnownToolchainExecutable(
          widget.toolId,
          widget.fallbackExecutable,
        );
    final locatingOrInstalling = _isLocating || isInstalling;

    return TpPreferenceStack(
      title: widget.title,
      subtitle: widget.subtitle,
      titleLeading: Icon(widget.leadingIcon, size: 28),
      body: Row(
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
          if (showInstallButton) ...[
            OutlinedButton.icon(
              key: widget.installKey,
              onPressed: locatingOrInstalling ? null : _install,
              icon: isInstalling
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      Icons.download_outlined,
                      size: context.tpIconSizes.md,
                    ),
              label: Text(
                isInstalling
                    ? l10n.cliInstallInstalling
                    : l10n.cliInstallButton,
              ),
            ),
            const SizedBox(width: 6),
          ],
          OutlinedButton.icon(
            key: widget.browseKey,
            onPressed: locatingOrInstalling ? null : _pickFile,
            icon: Icon(
              Icons.folder_open_outlined,
              size: context.tpIconSizes.md,
            ),
            label: Text(l10n.cliExecutablePathBrowse),
          ),
          const SizedBox(width: 6),
          TextButton(
            key: widget.resetKey,
            onPressed: locatingOrInstalling
                ? null
                : (isFallback ? _locate : _reset),
            child: _isLocating
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(
                    isFallback
                        ? l10n.cliExecutablePathLocate
                        : l10n.cliExecutablePathReset,
                  ),
          ),
        ],
      ),
      showDividerBelow: widget.showDividerBelow,
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
