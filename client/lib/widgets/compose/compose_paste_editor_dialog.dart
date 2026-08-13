// client/lib/widgets/compose/compose_paste_editor_dialog.dart
import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../l10n/l10n_extensions.dart';
import '../../services/compose/compose_clip.dart';

/// Opens the full-screen editor for a collapsed [ComposeClip]. Returns when
/// the page pops. Callers should `unawaited(...)` the returned future.
Future<void> showComposePasteEditor(
  BuildContext context,
  ComposeClip clip,
) {
  return Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => ComposePasteEditorPage(clip: clip),
    ),
  );
}

/// Full-screen page for viewing/editing the collapsed paste block. Seeded
/// from [ComposeClip.text]; commits via [ComposeClip.setExpanded] on Done,
/// discards on close, or clears via [ComposeClip.clear] on Remove.
class ComposePasteEditorPage extends StatefulWidget {
  const ComposePasteEditorPage({required this.clip, super.key});

  final ComposeClip clip;

  @override
  State<ComposePasteEditorPage> createState() => _ComposePasteEditorPageState();
}

class _ComposePasteEditorPageState extends State<ComposePasteEditorPage> {
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

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.composePasteEditorTitle(widget.clip.lineCount)),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          tooltip: l10n.cancel,
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          TextButton.icon(
            onPressed: _remove,
            icon: const Icon(Icons.delete_outline_rounded),
            label: Text(l10n.composePasteEditorRemove),
          ),
          FilledButton(
            onPressed: _commit,
            child: Text(l10n.composePasteEditorDone),
          ),
          SizedBox(width: spacing.lg),
        ],
      ),
      body: Padding(
        padding: EdgeInsets.all(spacing.lg),
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
    );
  }
}
