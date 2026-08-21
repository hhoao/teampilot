import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../widgets/app_toast/app_toast.dart';

import '../../cubits/session_preferences_cubit.dart';
import '../../cubits/ssh_profile_cubit.dart';
import '../../cubits/termux_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/install_job/install_job_key.dart';
import '../../models/session_preferences.dart';
import '../../models/ssh_profile.dart';
import '../../models/team_config.dart';
import '../../services/app/connection_mode_service.dart';
import '../../services/cli/cli_executable_discovery.dart';
import '../../services/cli/remote_cli_locator.dart';
import '../../services/install/install_job_enqueue.dart';
import '../../services/install/install_job_keys.dart';
import '../../services/install/install_job_registry.dart';
import '../../services/install/install_job_scope_resolver.dart';
import '../../services/ssh/ssh_client_factory.dart';
import '../../services/termux/termux_transport_profile.dart';
import '../../utils/debounce/debounce.dart';
import '../../widgets/cli/cli_brand_icon.dart';
import 'session_config_constants.dart';

class CliExecutablePathSettingsRow extends StatefulWidget {
  const CliExecutablePathSettingsRow({
    super.key,
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
    this.locateOverride,
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

  /// Test seam: when non-null, used instead of discovery.
  final Future<String?> Function()? locateOverride;

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

  String _storedPath() =>
      widget.cubit.state.preferences.cliExecutablePathFor(widget.cli.value);

  InstallJobKey _installJobKey(BuildContext context) {
    final scope = installJobScopeForContext(context);
    return InstallJobKeys.cli(widget.cli.value, scope: scope);
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
      await widget.cubit.setCliExecutablePathFor(widget.cli, path);
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
      // No SSH/Termux profile selected — fail without probing PATH.
      if (profile == null) return null;
      final client = await context.read<SshClientFactory>().clientForStorage(
        profile,
      );
      return CliExecutableDiscovery().locateRemoteCli(
        cli: widget.cli,
        run: RemoteCliLocator.runnerForClient(client),
      );
    }
    return CliExecutableDiscovery().locateLocalCli(widget.cli);
  }

  Future<void> _installCli() async {
    final registry = context.read<InstallJobRegistry>();
    final scope = installJobScopeForContext(context);
    final key = InstallJobKeys.cli(widget.cli.value, scope: scope);
    if (registry.isRunning(key)) {
      await registry.installCli(
        cli: widget.cli,
        scope: scope,
        title: context.l10n.cliInstallInstalling,
      );
      return;
    }

    setState(() {});
    try {
      final result = await registry.installCli(
        cli: widget.cli,
        scope: scope,
        title: context.l10n.cliInstallInstalling,
        onSucceeded: (installResult) async {
          final path = installResult.executablePath?.trim() ?? '';
          if (path.isEmpty) return;
          _persistDebouncer.cancel();
          await widget.cubit.setCliExecutablePathFor(widget.cli, path);
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
        state.preferences.cliExecutablePathFor(widget.cli.value),
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

    final isRemoteWorkPlane = context.select<ConnectionModeService, bool>(
      (service) => service.isRemoteWorkPlane,
    );
    final effective = widget.cubit.resolveExecutable(widget.cli);
    final isFallback = stored.trim().isEmpty;
    final fieldEmpty = _controller.text.trim().isEmpty;
    final hint = fieldEmpty ? '${l10n.cliExecutablePathUsing}$effective' : null;
    final showInstallButton =
        widget.installKey != null &&
        fieldEmpty &&
        !widget.cubit.hasKnownCliExecutable(widget.cli);
    final locatingOrInstalling = _isLocating || isInstalling;

    return TpPreferenceStack(
      title: widget.title,
      subtitle: widget.subtitle,
      titleLeading: CliBrandIcon(
        cli: widget.cli,
        label: widget.title,
        size: 28,
        borderRadius: 7,
      ),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisAlignment: MainAxisAlignment.start,
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
              onPressed: locatingOrInstalling ? null : _installCli,
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
            onPressed: (isRemoteWorkPlane || locatingOrInstalling)
                ? null
                : _pickFile,
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
