import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/shortcut_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../services/commands/command_l10n.dart';
import '../../services/commands/key_chord.dart';
import '../../services/commands/key_chord_formatter.dart';
import '../../services/commands/shortcut_dispatcher_handle.dart';
import '../app_dialog.dart';

/// Opens the press-to-bind capture modal for [commandId].
///
/// Returns `true` if the binding changed (rebind or unbind), `false`/`null`
/// if the user cancelled.
Future<bool?> showShortcutRebindDialog(
  BuildContext context, {
  required String commandId,
}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => ShortcutRebindDialog(commandId: commandId),
  );
}

final _modifierKeys = <LogicalKeyboardKey>{
  LogicalKeyboardKey.control,
  LogicalKeyboardKey.controlLeft,
  LogicalKeyboardKey.controlRight,
  LogicalKeyboardKey.shift,
  LogicalKeyboardKey.shiftLeft,
  LogicalKeyboardKey.shiftRight,
  LogicalKeyboardKey.alt,
  LogicalKeyboardKey.altLeft,
  LogicalKeyboardKey.altRight,
  LogicalKeyboardKey.meta,
  LogicalKeyboardKey.metaLeft,
  LogicalKeyboardKey.metaRight,
  LogicalKeyboardKey.fn,
  LogicalKeyboardKey.capsLock,
  LogicalKeyboardKey.numLock,
  LogicalKeyboardKey.scrollLock,
};

/// Press-to-bind capture modal: listens for the next non-modifier key while
/// suspending the root [ShortcutDispatcher] so app shortcuts don't fire and
/// steal the keypress.
class ShortcutRebindDialog extends StatefulWidget {
  const ShortcutRebindDialog({required this.commandId, super.key});

  final String commandId;

  @override
  State<ShortcutRebindDialog> createState() => _ShortcutRebindDialogState();
}

class _ShortcutRebindDialogState extends State<ShortcutRebindDialog> {
  final FocusNode _focusNode = FocusNode();
  bool? _previousDispatcherEnabled;

  /// Non-null while showing a "replace conflicting command?" confirmation
  /// for a just-captured chord instead of the plain listening state.
  KeyChord? _pendingChord;
  List<String> _pendingConflictIds = const [];
  String? _unsupportedKeyMessage;

  @override
  void initState() {
    super.initState();
    final dispatcher = ShortcutDispatcherHandle.instance;
    _previousDispatcherEnabled = dispatcher?.enabled;
    dispatcher?.enabled = false;
  }

  @override
  void dispose() {
    final dispatcher = ShortcutDispatcherHandle.instance;
    if (dispatcher != null && _previousDispatcherEnabled != null) {
      dispatcher.enabled = _previousDispatcherEnabled!;
    }
    _focusNode.dispose();
    super.dispose();
  }

  void _cancel() => Navigator.of(context).pop(false);

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.handled;

    if (_pendingChord != null) {
      // A conflict confirmation is showing; only Escape is meaningful here
      // (the confirm/cancel buttons handle the rest).
      if (event.logicalKey == LogicalKeyboardKey.escape) _cancel();
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.escape) {
      _cancel();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.backspace) {
      unawaited(_unbind());
      return KeyEventResult.handled;
    }
    if (_modifierKeys.contains(event.logicalKey)) {
      return KeyEventResult.handled;
    }

    String key;
    try {
      key = chordKeyForLogicalKey(event.logicalKey);
    } on ArgumentError {
      setState(() {
        _unsupportedKeyMessage = context.l10n.shortcutsPressShortcutUnsupportedKey;
      });
      return KeyEventResult.handled;
    }

    final mods = <KeyChordMod>[
      if (HardwareKeyboard.instance.isControlPressed) KeyChordMod.ctrl,
      if (HardwareKeyboard.instance.isMetaPressed) KeyChordMod.meta,
      if (HardwareKeyboard.instance.isAltPressed) KeyChordMod.alt,
      if (HardwareKeyboard.instance.isShiftPressed) KeyChordMod.shift,
    ];
    final chord = KeyChord(key: key, mods: mods);
    unawaited(_captureChord(chord));
    return KeyEventResult.handled;
  }

  Future<void> _captureChord(KeyChord chord) async {
    final cubit = context.read<ShortcutCubit>();
    final effective = cubit.effective;
    final conflictIds = [
      for (final entry in effective.entries)
        if (entry.key != widget.commandId && entry.value.contains(chord))
          entry.key,
    ];

    if (conflictIds.isEmpty) {
      await cubit.rebind(widget.commandId, [chord]);
      if (mounted) Navigator.of(context).pop(true);
      return;
    }

    setState(() {
      _pendingChord = chord;
      _pendingConflictIds = conflictIds;
      _unsupportedKeyMessage = null;
    });
  }

  Future<void> _confirmReplace() async {
    final chord = _pendingChord;
    if (chord == null) return;
    final cubit = context.read<ShortcutCubit>();
    final effective = cubit.effective;
    for (final id in _pendingConflictIds) {
      final remaining = (effective[id] ?? const [])
          .where((c) => c != chord)
          .toList(growable: false);
      await cubit.rebind(id, remaining);
    }
    await cubit.rebind(widget.commandId, [chord]);
    if (mounted) Navigator.of(context).pop(true);
  }

  void _cancelReplace() {
    setState(() {
      _pendingChord = null;
      _pendingConflictIds = const [];
    });
  }

  Future<void> _unbind() async {
    await context.read<ShortcutCubit>().unbind(widget.commandId);
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final title = titleForCommand(l10n, widget.commandId);

    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      skipTraversal: true,
      onKeyEvent: _onKeyEvent,
      child: AppDialog(
        maxWidth: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppDialogHeader(
              title: l10n.shortcutsPressShortcutTitle,
              onClose: _cancel,
            ),
            const SizedBox(height: 4),
            Text(
              title,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 12),
            if (_pendingChord != null)
              _ConflictConfirm(
                chordLabel: formatKeyChord(
                  _pendingChord!,
                  isMacOS: defaultIsMacOS(),
                ),
                conflictTitles: [
                  for (final id in _pendingConflictIds)
                    titleForCommand(l10n, id),
                ],
                onConfirm: () => unawaited(_confirmReplace()),
                onCancel: _cancelReplace,
              )
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    l10n.shortcutsPressShortcutHint,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (_unsupportedKeyMessage != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _unsupportedKeyMessage!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _ConflictConfirm extends StatelessWidget {
  const _ConflictConfirm({
    required this.chordLabel,
    required this.conflictTitles,
    required this.onConfirm,
    required this.onCancel,
  });

  final String chordLabel;
  final List<String> conflictTitles;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.shortcutsConflictMessage(conflictTitles.join(', ')),
        ),
        const SizedBox(height: 4),
        Text(
          chordLabel,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        AppDialogActions(
          showDividerAbove: false,
          children: [
            TextButton(onPressed: onCancel, child: Text(l10n.cancel)),
            FilledButton(
              onPressed: onConfirm,
              child: Text(l10n.shortcutsReplaceAction),
            ),
          ],
        ),
      ],
    );
  }
}