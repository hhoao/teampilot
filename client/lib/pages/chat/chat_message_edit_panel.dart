import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

/// Mobile "modify input" sheet. Returns true only after [onSubmit] accepted the
/// edit; dismissing (barrier / drag / X / cancel) returns false.
Future<bool> showChatMessageEditSheet(
  BuildContext context, {
  required String initialText,
  required String title,
  required String cancelLabel,
  required String sendLabel,
  required Future<bool> Function(String text) onSubmit,
}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    // A transparent barrier still blocks background taps (ModalBarrier), while
    // the "mask other parts" effect comes from per-message Opacity in the thread.
    barrierColor: Colors.transparent,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => _MobileMessageEditPanel(
      initialText: initialText,
      title: title,
      cancelLabel: cancelLabel,
      sendLabel: sendLabel,
      onSubmit: onSubmit,
    ),
  );
  return result ?? false;
}

class _MobileMessageEditPanel extends StatefulWidget {
  const _MobileMessageEditPanel({
    required this.initialText,
    required this.title,
    required this.cancelLabel,
    required this.sendLabel,
    required this.onSubmit,
  });

  final String initialText;
  final String title;
  final String cancelLabel;
  final String sendLabel;
  final Future<bool> Function(String text) onSubmit;

  @override
  State<_MobileMessageEditPanel> createState() =>
      _MobileMessageEditPanelState();
}

class _MobileMessageEditPanelState extends State<_MobileMessageEditPanel> {
  late final TextEditingController _controller;
  final FocusNode _focus = FocusNode();
  var _submitting = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText);
    _focus.requestFocus();
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    setState(() => _submitting = true);
    final accepted = await widget.onSubmit(text);
    if (!mounted) return;
    if (accepted) {
      Navigator.of(context).pop(true);
    } else {
      setState(() => _submitting = false);
    }
  }

  void _cancel() => Navigator.of(context).pop(false);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.title,
                      style: TpTextStyles.of(
                        context,
                      ).mdSemiboldColored(scheme.onSurface),
                    ),
                  ),
                  IconButton(
                    key: const ValueKey('chat-edit-sheet-close'),
                    onPressed: _cancel,
                    icon: const Icon(Icons.close_rounded),
                    color: scheme.onSurfaceVariant,
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                key: const ValueKey('chat-edit-sheet-field'),
                controller: _controller,
                focusNode: _focus,
                autofocus: true,
                maxLines: 5,
                minLines: 1,
                style: TpTextStyles.of(context).mdColored(scheme.onSurface),
                decoration: InputDecoration(
                  isDense: true,
                  filled: true,
                  fillColor: scheme.surfaceContainerHighest,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.all(12),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    key: const ValueKey('chat-edit-sheet-cancel'),
                    onPressed: _submitting ? null : _cancel,
                    child: Text(widget.cancelLabel),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    key: const ValueKey('chat-edit-sheet-send'),
                    onPressed: _submitting ? null : () => unawaited(_submit()),
                    child: _submitting
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(widget.sendLabel),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
