import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../l10n/l10n_extensions.dart';
import '../../services/follow_up/follow_up_queue.dart';

/// Finder key for the follow-up message queue strip.
const Key kSessionFollowUpQueueStripKey = ValueKey(
  'session-follow-up-queue-strip',
);

/// Collapsible list of staged follow-up messages for the active seat.
///
/// Visual language matches Cursor's Queued panel: quiet outline shell,
/// chevron + count header, hollow status dots, muted row actions.
class FollowUpQueueStrip extends StatefulWidget {
  const FollowUpQueueStrip({
    required this.queue,
    required this.onDelete,
    required this.onEdit,
    required this.onMoveUp,
    this.onResume,
    super.key,
  });

  final FollowUpQueue queue;
  final ValueChanged<String> onDelete;
  final void Function(String id, String content) onEdit;
  final ValueChanged<String> onMoveUp;
  final VoidCallback? onResume;

  @override
  State<FollowUpQueueStrip> createState() => _FollowUpQueueStripState();
}

class _FollowUpQueueStripState extends State<FollowUpQueueStrip>
    with SingleTickerProviderStateMixin {
  var _expanded = true;
  String? _editingId;
  late final TextEditingController _editController;
  late final AnimationController _chevron;

  @override
  void initState() {
    super.initState();
    _editController = TextEditingController();
    _chevron = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
      value: 1,
    );
  }

  @override
  void didUpdateWidget(FollowUpQueueStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_editingId != null &&
        !widget.queue.items.any((m) => m.id == _editingId)) {
      _cancelEdit();
    }
  }

  @override
  void dispose() {
    _editController.dispose();
    _chevron.dispose();
    super.dispose();
  }

  void _toggleExpanded() {
    final next = !_expanded;
    setState(() => _expanded = next);
    if (next) {
      _chevron.forward();
    } else {
      _chevron.reverse();
    }
  }

  void _startEdit(FollowUpQueuedMessage message) {
    setState(() {
      _editingId = message.id;
      _editController
        ..text = message.content
        ..selection = TextSelection.collapsed(offset: message.content.length);
    });
  }

  void _cancelEdit() {
    setState(() {
      _editingId = null;
      _editController.clear();
    });
  }

  void _submitEdit(String id) {
    final trimmed = _editController.text.trim();
    if (trimmed.isEmpty) {
      widget.onDelete(id);
    } else {
      widget.onEdit(id, trimmed);
    }
    _cancelEdit();
  }

  bool get _showResume =>
      widget.queue.drain == FollowUpDrainMode.paused &&
      widget.queue.items.isNotEmpty &&
      widget.onResume != null;

  @override
  Widget build(BuildContext context) {
    final items = widget.queue.items;
    if (items.isEmpty) return const SizedBox.shrink();

    final cs = Theme.of(context).colorScheme;
    final styles = TpTextStyles.of(context);
    final spacing = context.tpSpacing;
    final icons = context.tpIconSizes;
    final l10n = context.l10n;
    final border = Border.all(color: cs.outlineVariant.withValues(alpha: 0.55));

    return Padding(
      key: kSessionFollowUpQueueStripKey,
      padding: EdgeInsets.only(bottom: spacing.sm),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(10),
          border: border,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            TpHover(
              onTap: _toggleExpanded,
              padding: EdgeInsets.fromLTRB(
                spacing.sm,
                spacing.sm,
                spacing.xs,
                spacing.sm,
              ),
              child: Row(
                children: [
                  RotationTransition(
                    turns: Tween<double>(begin: -0.25, end: 0).animate(
                      CurvedAnimation(
                        parent: _chevron,
                        curve: Curves.easeOutCubic,
                      ),
                    ),
                    child: Icon(
                      Icons.expand_more,
                      size: icons.sm,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  SizedBox(width: spacing.xs),
                  Expanded(
                    child: Text(
                      l10n.sessionFollowUpQueued(items.length),
                      style: styles.smColored(cs.onSurfaceVariant),
                    ),
                  ),
                  if (_showResume)
                    IconButton(
                      icon: const Icon(Icons.play_arrow, size: 18),
                      tooltip: l10n.sessionFollowUpResume,
                      color: cs.primary,
                      visualDensity: VisualDensity.compact,
                      constraints: const BoxConstraints(
                        minWidth: 32,
                        minHeight: 32,
                      ),
                      onPressed: widget.onResume,
                    ),
                ],
              ),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: !_expanded
                  ? const SizedBox(width: double.infinity)
                  : Padding(
                      padding: EdgeInsets.fromLTRB(
                        spacing.sm,
                        0,
                        spacing.sm,
                        spacing.sm,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final (index, msg) in items.indexed)
                            Padding(
                              padding: EdgeInsets.only(
                                bottom: index == items.length - 1
                                    ? 0
                                    : spacing.xs,
                              ),
                              child: _QueueRow(
                                message: msg,
                                isEditing: _editingId == msg.id,
                                editController: _editController,
                                canMoveUp: index > 0,
                                onStartEdit: () => _startEdit(msg),
                                onSubmitEdit: () => _submitEdit(msg.id),
                                onCancelEdit: _cancelEdit,
                                onDelete: () => widget.onDelete(msg.id),
                                onMoveUp: () => widget.onMoveUp(msg.id),
                              ),
                            ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QueueRow extends StatelessWidget {
  const _QueueRow({
    required this.message,
    required this.isEditing,
    required this.editController,
    required this.canMoveUp,
    required this.onStartEdit,
    required this.onSubmitEdit,
    required this.onCancelEdit,
    required this.onDelete,
    required this.onMoveUp,
  });

  final FollowUpQueuedMessage message;
  final bool isEditing;
  final TextEditingController editController;
  final bool canMoveUp;
  final VoidCallback onStartEdit;
  final VoidCallback onSubmitEdit;
  final VoidCallback onCancelEdit;
  final VoidCallback onDelete;
  final VoidCallback onMoveUp;

  static const _actionConstraints = BoxConstraints(
    minWidth: 28,
    minHeight: 28,
  );

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final styles = TpTextStyles.of(context);
    final l10n = context.l10n;
    final muted = cs.onSurfaceVariant;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(8),
        // Editing stays inside the same quiet row chrome — no nested outline.
        border: isEditing
            ? Border.all(color: cs.outlineVariant.withValues(alpha: 0.7))
            : null,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 6, 2, 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(
              Icons.circle_outlined,
              size: 14,
              color: muted.withValues(alpha: 0.75),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: isEditing
                  ? Shortcuts(
                      shortcuts: const <ShortcutActivator, Intent>{
                        SingleActivator(LogicalKeyboardKey.escape):
                            DismissIntent(),
                      },
                      child: Actions(
                        actions: <Type, Action<Intent>>{
                          DismissIntent: CallbackAction<DismissIntent>(
                            onInvoke: (_) {
                              onCancelEdit();
                              return null;
                            },
                          ),
                        },
                        child: SizedBox(
                          // Match action IconButton hit target so caret/text
                          // sit on the same vertical midline as ○ / ✓ / ✕.
                          height: _actionConstraints.minHeight,
                          child: TextField(
                            controller: editController,
                            autofocus: true,
                            maxLines: 1,
                            style: styles.mdColored(cs.onSurface).copyWith(
                              height: 1.2,
                            ),
                            cursorColor: cs.onSurface,
                            cursorWidth: 1.2,
                            textAlignVertical: TextAlignVertical.center,
                            decoration: InputDecoration(
                              isDense: true,
                              filled: false,
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              disabledBorder: InputBorder.none,
                              errorBorder: InputBorder.none,
                              focusedErrorBorder: InputBorder.none,
                              contentPadding: EdgeInsets.zero,
                              isCollapsed: true,
                              hintText: l10n.sessionFollowUpAddPlaceholder,
                              hintStyle: styles
                                  .mdColored(muted.withValues(alpha: 0.7))
                                  .copyWith(height: 1.2),
                            ),
                            onSubmitted: (_) => onSubmitEdit(),
                          ),
                        ),
                      ),
                    )
                  : Text(
                      message.content,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: styles.mdColored(cs.onSurface),
                    ),
            ),
            if (isEditing) ...[
              IconButton(
                icon: const Icon(Icons.check, size: 16),
                tooltip: l10n.sessionFollowUpEdit,
                color: muted,
                visualDensity: VisualDensity.compact,
                constraints: _actionConstraints,
                padding: EdgeInsets.zero,
                onPressed: onSubmitEdit,
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 16),
                tooltip: MaterialLocalizations.of(context).cancelButtonLabel,
                color: muted,
                visualDensity: VisualDensity.compact,
                constraints: _actionConstraints,
                padding: EdgeInsets.zero,
                onPressed: onCancelEdit,
              ),
            ] else ...[
              IconButton(
                icon: const Icon(Icons.edit_outlined, size: 15),
                tooltip: l10n.sessionFollowUpEdit,
                color: muted,
                visualDensity: VisualDensity.compact,
                constraints: _actionConstraints,
                padding: EdgeInsets.zero,
                onPressed: onStartEdit,
              ),
              IconButton(
                icon: const Icon(Icons.arrow_upward, size: 15),
                tooltip: l10n.sessionFollowUpMoveUp,
                color: muted,
                visualDensity: VisualDensity.compact,
                constraints: _actionConstraints,
                padding: EdgeInsets.zero,
                onPressed: canMoveUp ? onMoveUp : null,
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 15),
                tooltip: l10n.sessionFollowUpDelete,
                color: muted,
                visualDensity: VisualDensity.compact,
                constraints: _actionConstraints,
                padding: EdgeInsets.zero,
                onPressed: onDelete,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
