import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../l10n/l10n_extensions.dart';
import '../../models/runtime_target.dart';
import '../../services/workspace/target_liveness.dart';

/// Returns selected `toTargetId`, or null if cancelled.
///
/// When [fromTargetId] is null, user picks among [deadTargetIds] first.
Future<String?> showWorkspaceDeadTargetRemapDialog({
  required BuildContext context,
  required String? fromTargetId,
  required List<String> deadTargetIds,
  required List<RuntimeTarget> selectable,
  required TargetLiveness liveness,
}) {
  return showDialog<String>(
    context: context,
    builder: (dialogContext) => _WorkspaceDeadTargetRemapDialog(
      fromTargetId: fromTargetId,
      deadTargetIds: deadTargetIds,
      selectable: selectable,
      liveness: liveness,
    ),
  );
}

class _WorkspaceDeadTargetRemapDialog extends StatefulWidget {
  const _WorkspaceDeadTargetRemapDialog({
    required this.fromTargetId,
    required this.deadTargetIds,
    required this.selectable,
    required this.liveness,
  });

  final String? fromTargetId;
  final List<String> deadTargetIds;
  final List<RuntimeTarget> selectable;
  final TargetLiveness liveness;

  @override
  State<_WorkspaceDeadTargetRemapDialog> createState() =>
      _WorkspaceDeadTargetRemapDialogState();
}

class _WorkspaceDeadTargetRemapDialogState
    extends State<_WorkspaceDeadTargetRemapDialog> {
  late String? _selectedFrom;
  String? _selectedTo;
  late Future<List<RuntimeTarget>> _toCandidatesFuture;

  bool get _showFromPicker =>
      widget.fromTargetId == null && widget.deadTargetIds.length > 1;

  @override
  void initState() {
    super.initState();
    _selectedFrom = widget.fromTargetId ??
        (widget.deadTargetIds.length == 1 ? widget.deadTargetIds.first : null);
    _reloadToCandidates();
  }

  Map<String, String> get _labelById => {
    for (final t in widget.selectable) t.id: t.label,
  };

  String _labelByIdOrId(String id) => _labelById[id] ?? id;

  void _reloadToCandidates() {
    final from = _selectedFrom;
    _toCandidatesFuture = from == null
        ? Future.value(const <RuntimeTarget>[])
        : _loadToCandidates(from);
    _selectedTo = null;
  }

  Future<List<RuntimeTarget>> _loadToCandidates(String from) async {
    final dead = widget.deadTargetIds.toSet();
    final alive = <RuntimeTarget>[];
    for (final target in widget.selectable) {
      if (target.id == from) continue;
      if (dead.contains(target.id)) continue;
      if (await widget.liveness.isAlive(target.id)) {
        alive.add(target);
      }
    }
    return alive;
  }

  void _onFromChanged(String? from) {
    if (from == null || from == _selectedFrom) return;
    setState(() {
      _selectedFrom = from;
      _reloadToCandidates();
    });
  }

  void _onToChanged(RuntimeTarget? target) {
    setState(() => _selectedTo = target?.id);
  }

  void _confirm() {
    final to = _selectedTo;
    if (to == null) return;
    Navigator.of(context).pop(to);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final from = _selectedFrom;
    final fromLabel = from == null ? '' : _labelByIdOrId(from);

    return TpDialog(
      maxWidth: 480,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TpDialogHeader(
            title: l10n.workspaceDeadTargetRemapTitle,
            onClose: () => Navigator.of(context).pop(),
          ),
          const SizedBox(height: 12),
          if (_showFromPicker) ...[
            Text(
              l10n.workspaceDeadTargetRemapPickFrom,
              style: Theme.of(context).textTheme.labelMedium,
            ),
            const SizedBox(height: 6),
            TpSelect<String>(
              items: widget.deadTargetIds,
              initialItem: from,
              hintText: l10n.workspaceDeadTargetRemapPickFrom,
              decoration: TpSelectDecorations.themed(context),
              itemLabel: _labelByIdOrId,
              searchable: widget.deadTargetIds.length >= 8,
              onChanged: _onFromChanged,
            ),
            const SizedBox(height: 16),
          ],
          if (from != null) ...[
            Text(l10n.workspaceDeadTargetRemapBody(fromLabel)),
            const SizedBox(height: 16),
            Text(
              l10n.workspaceDeadTargetRemapPickTo,
              style: Theme.of(context).textTheme.labelMedium,
            ),
            const SizedBox(height: 6),
            FutureBuilder<List<RuntimeTarget>>(
              future: _toCandidatesFuture,
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const SizedBox(
                    height: 40,
                    child: Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  );
                }

                final candidates = snapshot.data!;
                if (candidates.isEmpty) {
                  return Text(
                    l10n.workspaceDeadTargetRemapNothing,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  );
                }

                RuntimeTarget? selected;
                if (_selectedTo != null) {
                  for (final t in candidates) {
                    if (t.id == _selectedTo) {
                      selected = t;
                      break;
                    }
                  }
                }

                return TpSelect<RuntimeTarget>(
                  key: ValueKey(from),
                  items: candidates,
                  initialItem: selected,
                  hintText: l10n.workspaceDeadTargetRemapPickTo,
                  decoration: TpSelectDecorations.themed(context),
                  itemLabel: (t) => t.label,
                  searchable: candidates.length >= 8,
                  onChanged: _onToChanged,
                );
              },
            ),
          ],
          TpDialogActions(
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(l10n.cancel),
              ),
              FutureBuilder<List<RuntimeTarget>>(
                future: _toCandidatesFuture,
                builder: (context, snapshot) {
                  final canConfirm =
                      from != null &&
                      snapshot.hasData &&
                      snapshot.data!.isNotEmpty &&
                      _selectedTo != null;
                  return FilledButton(
                    onPressed: canConfirm ? _confirm : null,
                    child: Text(l10n.workspaceDeadTargetRemapConfirm),
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}
