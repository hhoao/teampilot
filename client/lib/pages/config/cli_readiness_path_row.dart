import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../l10n/l10n_extensions.dart';
import '../../utils/debounce/debounce.dart';
import 'session_config_constants.dart';

/// Label + editable path field + version suffix + action buttons.
///
/// Used twice on [CliReadinessCard]: CLI executable and ACP adapter.
class CliReadinessPathRow extends StatefulWidget {
  const CliReadinessPathRow({
    required this.label,
    required this.fieldKey,
    required this.storedPath,
    required this.discoveredPath,
    required this.version,
    required this.onPersist,
    required this.browseKey,
    required this.onBrowse,
    required this.locateOrResetKey,
    required this.locateLabel,
    required this.resetLabel,
    required this.onLocateOrReset,
    this.installKey,
    this.onInstall,
    this.installing = false,
    this.upgradeKey,
    this.onUpgrade,
    this.locating = false,
    this.enabled = true,
    super.key,
  });

  final String label;
  final Key fieldKey;
  final String storedPath;
  final String discoveredPath;
  final String version;
  final Future<void> Function(String value) onPersist;
  final Key browseKey;
  final VoidCallback? onBrowse;
  final Key locateOrResetKey;
  final String locateLabel;
  final String resetLabel;
  final VoidCallback? onLocateOrReset;
  final Key? installKey;
  final VoidCallback? onInstall;
  final bool installing;
  final Key? upgradeKey;
  final VoidCallback? onUpgrade;
  final bool locating;
  final bool enabled;

  @override
  State<CliReadinessPathRow> createState() => _CliReadinessPathRowState();
}

class _CliReadinessPathRowState extends State<CliReadinessPathRow> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  late final Debouncer _persistDebouncer;
  late String _lastSyncedDisplay;

  String get _displayPath {
    final stored = widget.storedPath.trim();
    if (stored.isNotEmpty) return stored;
    return widget.discoveredPath.trim();
  }

  bool get _storedEmpty => widget.storedPath.trim().isEmpty;

  bool get _busy => widget.installing || widget.locating;

  @override
  void initState() {
    super.initState();
    _persistDebouncer = Debouncer(
      tag: widget.fieldKey.toString(),
      duration: kSessionPathPersistDebounce,
    );
    _focusNode = FocusNode()..addListener(_onFocusChanged);
    _lastSyncedDisplay = _displayPath;
    _controller = TextEditingController(text: _lastSyncedDisplay);
  }

  @override
  void didUpdateWidget(CliReadinessPathRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.storedPath != widget.storedPath ||
        oldWidget.discoveredPath != widget.discoveredPath) {
      _syncFromState();
    }
  }

  @override
  void dispose() {
    _persistDebouncer.dispose();
    _focusNode.removeListener(_onFocusChanged);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _syncFromState() {
    final display = _displayPath;
    if (display == _lastSyncedDisplay) return;
    _persistDebouncer.cancel();
    _lastSyncedDisplay = display;
    if (_controller.text == display) return;
    _controller.value = TextEditingValue(
      text: display,
      selection: TextSelection.collapsed(offset: display.length),
    );
  }

  Future<void> _persistFromField() async {
    if (!mounted) return;
    final trimmed = _controller.text.trim();
    final stored = widget.storedPath.trim();
    if (trimmed == stored) {
      _restoreDisplayIfNeeded();
      return;
    }
    if (stored.isEmpty && trimmed == widget.discoveredPath.trim()) return;
    await widget.onPersist(trimmed);
  }

  void _restoreDisplayIfNeeded() {
    final display = _displayPath;
    if (_controller.text == display) return;
    _controller.value = TextEditingValue(
      text: display,
      selection: TextSelection.collapsed(offset: display.length),
    );
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

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final styles = TpTextStyles.of(context);
    final showInstall = widget.installKey != null && widget.onInstall != null;
    final showUpgrade = widget.upgradeKey != null && widget.onUpgrade != null;
    final actionsEnabled = widget.enabled && !_busy;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(width: 40, child: Text(widget.label, style: styles.mutedSm)),
        Expanded(
          child: TextField(
            key: widget.fieldKey,
            controller: _controller,
            focusNode: _focusNode,
            enabled: widget.enabled,
            decoration: InputDecoration(
              isDense: true,
              floatingLabelBehavior: FloatingLabelBehavior.never,
              suffix: Text(widget.version, style: styles.mutedSm),
            ),
            onChanged: widget.enabled
                ? (_) => _scheduleDebouncedPersist()
                : null,
            onSubmitted: widget.enabled ? (_) => _flushPersist() : null,
          ),
        ),
        if (widget.enabled) ...[
          if (showInstall) ...[
            const SizedBox(width: 6),
            OutlinedButton.icon(
              key: widget.installKey,
              onPressed: actionsEnabled ? widget.onInstall : null,
              icon: widget.installing
                  ? _spinner
                  : Icon(Icons.download_outlined, size: context.tpIconSizes.md),
              label: Text(
                widget.installing
                    ? l10n.cliInstallInstalling
                    : l10n.cliInstallButton,
              ),
            ),
          ],
          if (showUpgrade) ...[
            const SizedBox(width: 6),
            OutlinedButton.icon(
              key: widget.upgradeKey,
              onPressed: actionsEnabled ? widget.onUpgrade : null,
              icon: widget.installing
                  ? _spinner
                  : Icon(Icons.upgrade_outlined, size: context.tpIconSizes.md),
              label: Text(
                widget.installing
                    ? l10n.cliInstallUpgrading
                    : l10n.cliUpgradeButton,
              ),
            ),
          ],
          const SizedBox(width: 6),
          OutlinedButton.icon(
            key: widget.browseKey,
            onPressed: actionsEnabled ? widget.onBrowse : null,
            icon: Icon(
              Icons.folder_open_outlined,
              size: context.tpIconSizes.md,
            ),
            label: Text(l10n.cliExecutablePathBrowse),
          ),
          const SizedBox(width: 6),
          TextButton(
            key: widget.locateOrResetKey,
            onPressed: actionsEnabled ? widget.onLocateOrReset : null,
            child: widget.locating
                ? _spinner
                : Text(_storedEmpty ? widget.locateLabel : widget.resetLabel),
          ),
        ],
      ],
    );
  }
}

const _spinner = SizedBox(
  width: 16,
  height: 16,
  child: CircularProgressIndicator(strokeWidth: 2),
);
