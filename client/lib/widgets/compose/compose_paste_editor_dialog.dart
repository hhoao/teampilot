// client/lib/widgets/compose/compose_paste_editor_dialog.dart
import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../l10n/l10n_extensions.dart';
import '../../services/compose/compose_clip.dart';

/// Opens a bounded dialog for viewing/editing the collapsed paste block.
/// Returns when the dialog closes. Callers should `unawaited(...)` the
/// returned future.
Future<void> showComposePasteEditor(
  BuildContext context,
  ComposeClip clip,
) {
  return showDialog<void>(
    context: context,
    builder: (_) => ComposePasteEditorDialog(clip: clip),
  );
}

/// Compact, bounded dialog for viewing/editing the collapsed paste block.
/// Seeded from [ComposeClip.text]; commits via [ComposeClip.setExpanded] on
/// Done, discards on close, or clears via [ComposeClip.clear] on Remove.
class ComposePasteEditorDialog extends StatefulWidget {
  const ComposePasteEditorDialog({required this.clip, super.key});

  final ComposeClip clip;

  @override
  State<ComposePasteEditorDialog> createState() => _ComposePasteEditorDialogState();
}

class _ComposePasteEditorDialogState extends State<ComposePasteEditorDialog> {
  late final TextEditingController _editor;

  @override
  void initState() {
    super.initState();
    _editor = TextEditingController(text: widget.clip.text ?? '');
  }

  @override
  void dispose() {
    _editor.dispose();
    super.dispose();
  }

  void _commit() {
    widget.clip.setExpanded(_editor.text);
    Navigator.of(context).pop();
  }

  void _remove() {
    widget.clip.clear();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final spacing = context.tpSpacing;
    final styles = TpTextStyles.of(context);
    final maxHeight = MediaQuery.sizeOf(context).height * 0.65;

    return Dialog(
      insetPadding: EdgeInsets.all(spacing.lg),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 720,
          minHeight: 320,
          maxHeight: maxHeight,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.max,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.only(left: spacing.lg, right: spacing.xs),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.composePasteEditorTitle(widget.clip.lineCount),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: styles.lgSemibold,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    tooltip: l10n.cancel,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            SizedBox(height: spacing.sm),
            Expanded(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: spacing.lg),
                child: ScrollConfiguration(
                  behavior: const TpTextareaScrollBehavior(),
                  child: TextField(
                    controller: _editor,
                    autofocus: true,
                    expands: true,
                    minLines: null,
                    maxLines: null,
                    keyboardType: TextInputType.multiline,
                    textAlignVertical: TextAlignVertical.top,
                    style: Theme.of(context).textTheme.bodyMedium,
                    decoration: tpMultilineInputDecoration(context),
                  ),
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.all(spacing.lg),
              child: Row(
                children: [
                  TextButton.icon(
                    onPressed: _remove,
                    icon: const Icon(Icons.delete_outline_rounded),
                    label: Text(l10n.composePasteEditorRemove),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(l10n.cancel),
                  ),
                  SizedBox(width: spacing.sm),
                  FilledButton(
                    onPressed: _commit,
                    child: Text(l10n.composePasteEditorDone),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
