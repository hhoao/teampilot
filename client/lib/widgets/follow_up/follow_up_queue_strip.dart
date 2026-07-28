import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../l10n/l10n_extensions.dart';
import '../../services/follow_up/follow_up_queue.dart';

/// Finder key for the follow-up message queue strip.
const Key kSessionFollowUpQueueStripKey = ValueKey(
  'session-follow-up-queue-strip',
);

/// Collapsible list of staged follow-up messages for the active seat.
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
    final l10n = context.l10n;

    return Padding(
      key: kSessionFollowUpQueueStripKey,
      padding: EdgeInsets.only(bottom: spacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _toggleExpanded,
              child: Row(
                children: [
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
                      onPressed: widget.onResume,
                    ),
                  RotationTransition(
                    turns: Tween<double>(begin: 0, end: 0.5).animate(
                      CurvedAnimation(
                        parent: _chevron,
                        curve: Curves.easeOutCubic,
                      ),
                    ),
                    child: Icon(
                      Icons.expand_more,
                      size: context.tpIconSizes.sm,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: !_expanded
                ? const SizedBox(width: double.infinity)
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(height: spacing.xs),
                      for (final (index, msg) in items.indexed)
                        Padding(
                          padding: EdgeInsets.only(bottom: spacing.xs),
                          child: _QueueRow(
                            message: msg,
                            isEditing: _editingId == msg.id,
                            editController: _editController,
                            canMoveUp: index > 0,
                            onStartEdit: () => _startEdit(msg),
                            onSubmitEdit: () => _submitEdit(msg.id),
                            onDelete: () => widget.onDelete(msg.id),
                            onMoveUp: () => widget.onMoveUp(msg.id),
                          ),
                        ),
                    ],
                  ),
          ),
        ],
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
    required this.onDelete,
    required this.onMoveUp,
  });

  final FollowUpQueuedMessage message;
  final bool isEditing;
  final TextEditingController editController;
  final bool canMoveUp;
  final VoidCallback onStartEdit;
  final VoidCallback onSubmitEdit;
  final VoidCallback onDelete;
  final VoidCallback onMoveUp;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final styles = TpTextStyles.of(context);
    final l10n = context.l10n;

    return Material(
      color: cs.secondaryContainer,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.schedule,
              size: 18,
              color: cs.onSecondaryContainer,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: isEditing
                  ? TextField(
                      controller: editController,
                      autofocus: true,
                      maxLines: 3,
                      minLines: 1,
                      style: styles.mdColored(cs.onSecondaryContainer),
                      decoration: InputDecoration(
                        isDense: true,
                        border: InputBorder.none,
                        hintText: l10n.sessionFollowUpAddPlaceholder,
                      ),
                      onSubmitted: (_) => onSubmitEdit(),
                    )
                  : Text(
                      message.content,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: styles.mdColored(cs.onSecondaryContainer),
                    ),
            ),
            if (isEditing)
              IconButton(
                icon: const Icon(Icons.check, size: 16),
                tooltip: l10n.sessionFollowUpEdit,
                color: cs.onSecondaryContainer,
                onPressed: onSubmitEdit,
              )
            else ...[
              IconButton(
                icon: const Icon(Icons.edit, size: 16),
                tooltip: l10n.sessionFollowUpEdit,
                color: cs.onSecondaryContainer,
                onPressed: onStartEdit,
              ),
              IconButton(
                icon: const Icon(Icons.arrow_upward, size: 16),
                tooltip: l10n.sessionFollowUpMoveUp,
                color: cs.onSecondaryContainer,
                onPressed: canMoveUp ? onMoveUp : null,
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 16),
                tooltip: l10n.sessionFollowUpDelete,
                color: cs.onSecondaryContainer,
                onPressed: onDelete,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
