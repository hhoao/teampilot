import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/repo_clone_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/runtime_target.dart';
import '../../models/workspace_folder.dart';
import '../../services/storage/home_target_controller.dart';
import '../../services/storage/work_target_canonicalizer.dart';
import '../../services/workspace/repo_clone_service.dart';
import '../../utils/workspace/workspace_path_picker.dart';
import '../../widgets/app_toast/app_toast.dart';
import '../../widgets/workspace_create_directory_picker.dart';

typedef RepoCloneParentDirPicker = Future<String?> Function(
  BuildContext context,
  String targetId,
);

/// Opens the "Clone Repository" modal, starts the clone through
/// [RepoCloneCubit], and surfaces a started toast.
Future<void> showCloneRepositoryDialog(BuildContext context) async {
  final request = await showDialog<RepoCloneRequest>(
    context: context,
    builder: (_) => const HomeCloneRepositoryDialog(),
  );
  if (request == null || !context.mounted) return;
  context.read<RepoCloneCubit>().startClone(request);
  AppToast.show(
    context,
    message: context.l10n.cloneRepositoryStarted(request.url),
    variant: TpToastVariant.info,
  );
}

/// Centered modal collecting a git URL + destination for `git clone`.
///
/// Modeled on [HomeNewWorkspaceDialog]: [TpDialog] + [TpForm] shell, target
/// selector fed by [HomeTargetController.listSelectable], and a
/// [WorkspaceCreateNameField] for the clone folder name.
class HomeCloneRepositoryDialog extends StatefulWidget {
  const HomeCloneRepositoryDialog({super.key, this.picker});

  /// Parent-directory picker seam; overridden in widget tests.
  final RepoCloneParentDirPicker? picker;

  @override
  State<HomeCloneRepositoryDialog> createState() =>
      _HomeCloneRepositoryDialogState();
}

class _HomeCloneRepositoryDialogState extends State<HomeCloneRepositoryDialog> {
  final _formKey = GlobalKey<TpFormState>();
  late final TextEditingController _urlController;
  late final TextEditingController _dirNameController;
  var _targetId = WorkspaceFolder.localTargetId;
  var _parentDir = '';
  var _targetIdInitialized = false;
  var _dirNameTouched = false;
  var _autofillingDirName = false;

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController();
    _dirNameController = TextEditingController();
    _dirNameController.addListener(_onDirNameChanged);
  }

  /// Marks the dir-name field as user-touched unless the change came from the
  /// URL-derived autofill.
  void _onDirNameChanged() {
    if (_autofillingDirName) return;
    _dirNameTouched = true;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_targetIdInitialized) return;
    _targetIdInitialized = true;
    _targetId = WorkTargetCanonicalizer.defaultFolderTargetId(
      context.read<HomeTargetController>().current,
    );
  }

  @override
  void dispose() {
    _urlController.dispose();
    _dirNameController.dispose();
    super.dispose();
  }

  void _onTargetChanged(String next) {
    if (next == _targetId) return;
    setState(() => _targetId = next);
  }

  void _onUrlChanged(String url) {
    final derived = repoCloneDirNameFromUrl(url);
    if (!_dirNameTouched && derived.isNotEmpty) {
      _autofillingDirName = true;
      _dirNameController.text = derived;
      _autofillingDirName = false;
    }
  }

  Future<void> _pickParentDir() async {
    final picker =
        widget.picker ??
        (context, targetId) =>
            pickWorkspaceDirectoryPath(context, targetId: targetId);
    final picked = await picker(context, _targetId);
    final trimmed = picked?.trim() ?? '';
    if (trimmed.isEmpty || !mounted) return;
    setState(() => _parentDir = trimmed);
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    Navigator.of(context).pop(
      RepoCloneRequest(
        url: _urlController.text.trim(),
        targetId: _targetId,
        parentDir: _parentDir,
        dirName: _dirNameController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final styles = TpTextStyles.of(context);
    final derivedHint = _dirNameController.text.isEmpty
        ? repoCloneDirNameFromUrl(_urlController.text)
        : '';
    final hint = derivedHint.isNotEmpty
        ? derivedHint
        : l10n.cloneRepositoryUrlHint;

    return TpDialog(
      maxWidth: 640,
      scrollable: true,
      child: TpForm(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TpDialogHeader(title: l10n.cloneRepositoryTitle),
            const SizedBox(height: 16),
            TpFormField<String>(
              id: 'url',
              label: Text(
                l10n.cloneRepositoryUrlLabel,
                style: styles.xsColored(cs.onSurfaceVariant),
              ),
              builder: (state) => TpInput(
                controller: _urlController,
                onChanged: _onUrlChanged,
                decoration: InputDecoration(
                  hintText: l10n.cloneRepositoryUrlHint,
                ),
              ),
              validator: (value) {
                final url = _urlController.text.trim();
                return repoCloneUrlLooksValid(url)
                    ? null
                    : l10n.cloneRepositoryUrlInvalid;
              },
            ),
            const SizedBox(height: 16),
            _TargetRow(targetId: _targetId, onChanged: _onTargetChanged),
            const SizedBox(height: 16),
            _ParentDirRow(
              parentDir: _parentDir,
              onPick: () => unawaited(_pickParentDir()),
            ),
            TpFormField<bool>(
              id: 'parentDir',
              builder: (_) => const SizedBox.shrink(),
              validator: (_) => _parentDir.trim().isEmpty
                  ? l10n.cloneRepositoryParentDirRequired
                  : null,
            ),
            const SizedBox(height: 8),
            WorkspaceCreateNameField(
              controller: _dirNameController,
              hint: hint,
              onSubmitted: (_) => _submit(),
            ),
            TpFormField<bool>(
              id: 'dirName',
              builder: (_) => const SizedBox.shrink(),
              validator: (_) => _dirNameController.text.trim().isEmpty
                  ? l10n.cloneRepositoryDirNameRequired
                  : null,
            ),
            const SizedBox(height: 28),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(l10n.cancel),
                ),
                const SizedBox(width: 12),
                FilledButton(
                  onPressed: _submit,
                  child: Text(l10n.cloneRepositorySubmit),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Machine dropdown fed by [HomeTargetController.listSelectable], following the
/// target-row shape of [WorkspaceCreateDirectoryPicker].
class _TargetRow extends StatefulWidget {
  const _TargetRow({required this.targetId, required this.onChanged});

  final String targetId;
  final ValueChanged<String> onChanged;

  @override
  State<_TargetRow> createState() => _TargetRowState();
}

class _TargetRowState extends State<_TargetRow> {
  late Future<List<RuntimeTarget>> _targets;

  @override
  void initState() {
    super.initState();
    _targets = context.read<HomeTargetController>().listSelectable();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final styles = TpTextStyles.of(context);

    return FutureBuilder<List<RuntimeTarget>>(
      future: _targets,
      builder: (context, snapshot) {
        final targets = snapshot.data ?? const <RuntimeTarget>[];
        final targetIds = targets.map((t) => t.id).toSet();
        final entries = <(String, String)>[
          for (final t in targets) (t.id, t.label),
          if (!targetIds.contains(widget.targetId))
            (widget.targetId, widget.targetId),
        ];

        return Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.6)),
          ),
          child: Row(
            children: [
              Icon(Icons.dns_outlined, size: 20, color: cs.onSurfaceVariant),
              const SizedBox(width: 10),
              Text(
                l10n.cloneRepositoryTargetLabel,
                style: styles.mdSemiboldColored(cs.onSurface),
                maxLines: 1,
                softWrap: false,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Tooltip(
                  message: entries
                      .firstWhere(
                        (e) => e.$1 == widget.targetId,
                        orElse: () => (widget.targetId, widget.targetId),
                      )
                      .$2,
                  waitDuration: const Duration(milliseconds: 400),
                  child: TpCompactSelect<String>(
                    value: widget.targetId,
                    entries: entries,
                    onChanged: (id) {
                      if (id == null || id == widget.targetId) return;
                      widget.onChanged(id);
                    },
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// "Clone into folder" row: pick button + picked path, validated non-empty.
class _ParentDirRow extends StatelessWidget {
  const _ParentDirRow({required this.parentDir, required this.onPick});

  final String parentDir;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final styles = TpTextStyles.of(context);
    final hasDir = parentDir.trim().isNotEmpty;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: hasDir
              ? cs.primary.withValues(alpha: 0.6)
              : cs.outlineVariant.withValues(alpha: 0.6),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(
                Icons.drive_folder_upload_outlined,
                size: 20,
                color: cs.onSurfaceVariant,
              ),
              const SizedBox(width: 10),
              Text(
                l10n.cloneRepositoryParentDirLabel,
                style: styles.mdSemiboldColored(cs.onSurface),
                maxLines: 1,
                softWrap: false,
              ),
              const Spacer(),
              OutlinedButton(
                onPressed: onPick,
                child: Text(l10n.homeWorkspaceNewWorkspaceChooseDirectory),
              ),
            ],
          ),
          if (hasDir) ...[
            const SizedBox(height: 8),
            Text(
              parentDir,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: styles.smColored(cs.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }
}
