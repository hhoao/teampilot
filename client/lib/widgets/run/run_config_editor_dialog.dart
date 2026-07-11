import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/run_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/run/launch_configuration.dart';
import '../../models/workspace_folder.dart';
import '../../services/run/process_launch_schema.dart';
import '../../theme/app_dialog_theme.dart';
import '../../theme/app_text_styles.dart';
import '../../theme/workspace_surface_layers.dart';
import '../app_dialog.dart';
import 'launch_config_schema_form.dart';

const double _kEditorWidth = 840;
const double _kEditorHeight = 560;
const double _kLeftPaneWidth = 240;
const String _kNewListKey = '__new__';
const _kCommonSchemaKeys = {'name', 'type', 'id', 'request'};

/// Opens the dual-pane Edit Configurations dialog.
Future<void> showRunConfigEditorDialog(
  BuildContext context, {
  required String workspaceId,
  OwnedLaunchConfiguration? initial,
  bool createNew = false,
  String? initialType,
  WorkspaceFolder? folder,
}) {
  final cubit = context.read<RunCubit>();
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => BlocProvider<RunCubit>.value(
      value: cubit,
      child: RunConfigEditorDialog(
        workspaceId: workspaceId,
        initial: initial,
        createNew: createNew,
        initialType: initialType,
        folder: folder,
      ),
    ),
  );
}

/// Dual-pane editor for workspace launch configurations (not compounds).
class RunConfigEditorDialog extends StatefulWidget {
  const RunConfigEditorDialog({
    required this.workspaceId,
    this.initial,
    this.createNew = false,
    this.initialType,
    this.folder,
    super.key,
  });

  final String workspaceId;
  final OwnedLaunchConfiguration? initial;
  final bool createNew;
  final String? initialType;
  final WorkspaceFolder? folder;

  @override
  State<RunConfigEditorDialog> createState() => _RunConfigEditorDialogState();
}

enum _DirtyChoice { apply, discard, cancel }

class _RunConfigEditorDialogState extends State<RunConfigEditorDialog> {
  String? _selectedKey;
  OwnedLaunchConfiguration? _draft;
  OwnedLaunchConfiguration? _baseline;
  bool _awaitingFolder = false;
  List<String> _formErrors = const [];

  bool get _isDirty =>
      _draft != null && _baseline != null && _draft != _baseline;

  @override
  void initState() {
    super.initState();
    final cubit = context.read<RunCubit>();
    if (widget.createNew) {
      final folders = cubit.folders;
      final target = widget.folder;
      if (target != null) {
        _beginCreate(target);
      } else if (folders.length == 1) {
        _beginCreate(folders.single);
      } else if (folders.length > 1) {
        _awaitingFolder = true;
      }
    } else if (widget.initial != null) {
      _selectOwned(widget.initial!);
    } else if (cubit.state.configurations.isNotEmpty) {
      _selectOwned(cubit.state.configurations.first);
    }
  }

  void _beginCreate(WorkspaceFolder folder) {
    final cubit = context.read<RunCubit>();
    final draft = cubit.createConfiguration(
      folder: folder,
      type: widget.initialType ?? ProcessLaunchSchema.typeName,
    );
    _selectedKey = _kNewListKey;
    _draft = draft;
    _baseline = draft;
    _awaitingFolder = false;
    _formErrors = const [];
  }

  void _selectOwned(OwnedLaunchConfiguration owned) {
    _selectedKey = owned.selectionKey;
    _draft = owned;
    _baseline = owned;
    _formErrors = const [];
  }

  Map<String, Object?> _schemaFor(String type) {
    final cubit = context.read<RunCubit>();
    final raw =
        cubit.schemaForType(type) ??
        (type == ProcessLaunchSchema.typeName
            ? ProcessLaunchSchema.configurationSchema
            : const <String, Object?>{});
    return _filterCommonSchemaProps(raw);
  }

  Future<_DirtyChoice?> _promptDirty() {
    final l10n = context.l10n;
    return showDialog<_DirtyChoice>(
      context: context,
      builder: (ctx) {
        return AppDialog(
          maxWidth: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppDialogHeader(
                title: l10n.runDiscardChangesTitle,
                onClose: () => Navigator.of(ctx).pop(_DirtyChoice.cancel),
              ),
              const SizedBox(height: 12),
              Text(l10n.runDiscardChangesMessage),
              AppDialogActions(
                children: [
                  TextButton(
                    onPressed: () =>
                        Navigator.of(ctx).pop(_DirtyChoice.cancel),
                    child: Text(l10n.cancel),
                  ),
                  TextButton(
                    onPressed: () =>
                        Navigator.of(ctx).pop(_DirtyChoice.discard),
                    child: Text(l10n.runDiscard),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.of(ctx).pop(_DirtyChoice.apply),
                    child: Text(l10n.runApply),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Future<bool> _ensureCleanForNavigation() async {
    if (!_isDirty) return true;
    final choice = await _promptDirty();
    if (!mounted) return false;
    switch (choice) {
      case _DirtyChoice.apply:
        return _applyCurrent();
      case _DirtyChoice.discard:
        setState(() {
          _draft = _baseline;
          _formErrors = const [];
        });
        return true;
      case _DirtyChoice.cancel:
      case null:
        return false;
    }
  }

  Future<bool> _applyCurrent() async {
    final draft = _draft;
    if (draft == null) return false;
    final cubit = context.read<RunCubit>();
    await cubit.saveConfiguration(draft);
    if (!mounted) return false;
    final error = cubit.state.errorMessage;
    if (error != null && error.isNotEmpty) {
      setState(() => _formErrors = [error]);
      return false;
    }

    final saved =
        cubit.state.selectedConfiguration ??
        cubit.state.configurations
            .where(
              (c) =>
                  c.owner == draft.owner &&
                  c.configuration.type == draft.configuration.type &&
                  c.configuration.name == draft.configuration.name,
            )
            .firstOrNull ??
        cubit.state.configurations
            .where((c) => c.selectionKey == draft.selectionKey)
            .firstOrNull;

    if (!mounted) return false;
    setState(() {
      if (saved != null) {
        _draft = saved;
        _baseline = saved;
        _selectedKey = saved.selectionKey;
      } else {
        _baseline = _draft;
      }
      _formErrors = const [];
    });
    return true;
  }

  Future<void> _onOk() async {
    final navigator = Navigator.of(context);
    final draft = _draft;
    final shouldSave =
        draft != null && (_isDirty || draft.configuration.id.isEmpty);
    if (shouldSave) {
      final cubit = context.read<RunCubit>();
      await cubit.saveConfiguration(draft);
      if (!mounted) return;
      final error = cubit.state.errorMessage;
      if (error != null && error.isNotEmpty) {
        setState(() => _formErrors = [error]);
        return;
      }
    }
    navigator.pop();
  }

  Future<void> _onApply() async {
    await _applyCurrent();
  }

  Future<void> _onCancel() async {
    if (_isDirty) {
      final choice = await _promptDirty();
      if (!mounted) return;
      switch (choice) {
        case _DirtyChoice.apply:
          final ok = await _applyCurrent();
          if (!ok || !mounted) return;
          Navigator.of(context).pop();
        case _DirtyChoice.discard:
          Navigator.of(context).pop();
        case _DirtyChoice.cancel:
        case null:
          return;
      }
      return;
    }
    Navigator.of(context).pop();
  }

  Future<void> _onSelectKey(String listKey, OwnedLaunchConfiguration? owned) async {
    if (listKey == _selectedKey) return;
    final clean = await _ensureCleanForNavigation();
    if (!clean || !mounted) return;
    setState(() {
      if (owned != null) {
        _selectOwned(owned);
      }
    });
  }

  Future<void> _onAdd() async {
    final clean = await _ensureCleanForNavigation();
    if (!clean || !mounted) return;
    final cubit = context.read<RunCubit>();
    final folders = cubit.folders;
    if (folders.isEmpty) return;
    if (folders.length == 1) {
      setState(() => _beginCreate(folders.single));
      return;
    }
    setState(() {
      _awaitingFolder = true;
      _selectedKey = null;
      _draft = null;
      _baseline = null;
      _formErrors = const [];
    });
  }

  Future<void> _onDelete() async {
    final draft = _draft;
    if (draft == null || draft.configuration.id.isEmpty) {
      // Discard unsaved new draft.
      setState(() {
        final configs = context.read<RunCubit>().state.configurations;
        if (configs.isNotEmpty) {
          _selectOwned(configs.first);
        } else {
          _selectedKey = null;
          _draft = null;
          _baseline = null;
        }
        _formErrors = const [];
      });
      return;
    }

    final cubit = context.read<RunCubit>();
    final l10n = context.l10n;
    final running = cubit.hasRunning(draft.selectionKey);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AppDialog(
          maxWidth: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppDialogHeader(
                title: l10n.runDeleteConfiguration,
                onClose: () => Navigator.of(ctx).pop(false),
              ),
              const SizedBox(height: 12),
              Text(
                l10n.runDeleteConfigurationConfirm(
                  draft.configuration.name.isEmpty
                      ? draft.configId
                      : draft.configuration.name,
                ),
              ),
              AppDialogActions(
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(false),
                    child: Text(l10n.cancel),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.of(ctx).pop(true),
                    child: Text(
                      running ? l10n.runStopAndDelete : l10n.runDeleteConfiguration,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
    if (confirmed != true || !mounted) return;

    await cubit.deleteConfiguration(draft);
    if (!mounted) return;
    final remaining = cubit.state.configurations;
    setState(() {
      if (remaining.isNotEmpty) {
        _selectOwned(remaining.first);
      } else {
        _selectedKey = null;
        _draft = null;
        _baseline = null;
      }
      _formErrors = const [];
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final media = MediaQuery.of(context);
    final dialogWidth = _kEditorWidth.clamp(
      0.0,
      media.size.width - kAppDialogInsetExtent,
    );
    // Leave room for [Dialog] insetPadding so the footer stays hittable.
    final dialogHeight = _kEditorHeight.clamp(
      0.0,
      media.size.height - kAppDialogInsetExtent * 2,
    );

    return AppDialog(
      maxWidth: dialogWidth,
      maxHeight: dialogHeight,
      contentPadding: EdgeInsets.zero,
      backgroundColor: cs.workspacePage,
      child: SizedBox(
        width: dialogWidth,
        height: dialogHeight,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                kAppDialogContentHorizontalInset,
                16,
                8,
                0,
              ),
              child: AppDialogHeader(
                title: l10n.runEditConfigurations,
                onClose: _onCancel,
                horizontalInset: kAppDialogContentHorizontalInset,
              ),
            ),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: _kLeftPaneWidth,
                    child: _LeftPane(
                      selectedKey: _selectedKey,
                      draft: _draft,
                      onSelect: _onSelectKey,
                      onAdd: _onAdd,
                      onDelete: _draft == null ? null : _onDelete,
                    ),
                  ),
                  VerticalDivider(
                    width: 1,
                    thickness: 1,
                    color: cs.outlineVariant.withValues(alpha: 0.5),
                  ),
                  Expanded(child: _buildRightPane(context)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                kAppDialogContentHorizontalInset,
                0,
                kAppDialogContentHorizontalInset,
                16,
              ),
              child: AppDialogActions(
                horizontalInset: kAppDialogContentHorizontalInset,
                children: [
                  TextButton(
                    key: const Key('run-config-editor-cancel'),
                    onPressed: _onCancel,
                    child: Text(l10n.cancel),
                  ),
                  TextButton(
                    key: const Key('run-config-editor-apply'),
                    onPressed: _draft == null || _awaitingFolder
                        ? null
                        : _onApply,
                    child: Text(l10n.runApply),
                  ),
                  FilledButton(
                    key: const Key('run-config-editor-ok'),
                    onPressed: _draft == null || _awaitingFolder
                        ? null
                        : _onOk,
                    child: Text(l10n.ok),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRightPane(BuildContext context) {
    final l10n = context.l10n;
    final styles = AppTextStyles.of(context);
    final cubit = context.read<RunCubit>();

    if (_awaitingFolder) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.runSelectFolder, style: styles.sectionTitle),
            const SizedBox(height: 12),
            for (final folder in cubit.folders)
              ListTile(
                title: Text(_folderLabel(folder)),
                onTap: () => setState(() => _beginCreate(folder)),
              ),
          ],
        ),
      );
    }

    final draft = _draft;
    if (draft == null) {
      return Center(
        child: Text(
          l10n.runSelectConfiguration,
          style: styles.bodySmall,
        ),
      );
    }

    final type = draft.configuration.type;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InputDecorator(
            decoration: InputDecoration(
              labelText: l10n.runConfigurationType,
              border: const OutlineInputBorder(),
              isDense: true,
            ),
            child: Text(type, style: styles.body),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: SingleChildScrollView(
              child: LaunchConfigSchemaForm(
                key: ValueKey<String>(
                  '${_selectedKey ?? ''}|$type|${draft.configuration.id}',
                ),
                value: draft.configuration,
                schema: _schemaFor(type),
                errors: _formErrors,
                onChanged: (next) {
                  setState(() {
                    _draft = OwnedLaunchConfiguration(
                      owner: draft.owner,
                      configuration: next,
                    );
                  });
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LeftPane extends StatelessWidget {
  const _LeftPane({
    required this.selectedKey,
    required this.draft,
    required this.onSelect,
    required this.onAdd,
    required this.onDelete,
  });

  final String? selectedKey;
  final OwnedLaunchConfiguration? draft;
  final void Function(String listKey, OwnedLaunchConfiguration? owned) onSelect;
  final VoidCallback onAdd;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final styles = AppTextStyles.of(context);
    final cs = Theme.of(context).colorScheme;
    final cubit = context.watch<RunCubit>();
    final multiFolder = cubit.folders.length > 1;
    final configs = cubit.state.configurations;
    final showingNew =
        selectedKey == _kNewListKey &&
        draft != null &&
        draft!.configuration.id.isEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              for (final owned in configs)
                _ConfigListTile(
                  itemKey: Key('run-config-list-item-${owned.configId}'),
                  title: owned.configuration.name.isEmpty
                      ? owned.configId
                      : owned.configuration.name,
                  subtitle: multiFolder ? _folderLabel(owned.owner) : null,
                  selected: selectedKey == owned.selectionKey,
                  onTap: () => onSelect(owned.selectionKey, owned),
                ),
              if (showingNew)
                _ConfigListTile(
                  itemKey: const Key('run-config-list-item-new'),
                  title: draft!.configuration.name.isEmpty
                      ? l10n.runAddConfiguration
                      : draft!.configuration.name,
                  subtitle: multiFolder ? _folderLabel(draft!.owner) : null,
                  selected: true,
                  onTap: () {},
                ),
            ],
          ),
        ),
        Divider(
          height: 1,
          thickness: 1,
          color: cs.outlineVariant.withValues(alpha: 0.5),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
          child: Row(
            children: [
              Expanded(
                child: TextButton.icon(
                  key: const Key('run-config-editor-add'),
                  onPressed: onAdd,
                  icon: const Icon(Icons.add, size: 18),
                  label: Text(l10n.runAddConfiguration, style: styles.bodySmall),
                ),
              ),
              IconButton(
                key: const Key('run-config-editor-delete'),
                tooltip: l10n.runDeleteConfiguration,
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ConfigListTile extends StatelessWidget {
  const _ConfigListTile({
    required this.itemKey,
    required this.title,
    required this.selected,
    required this.onTap,
    this.subtitle,
  });

  final Key itemKey;
  final String title;
  final String? subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final styles = AppTextStyles.of(context);
    return Material(
      color: selected
          ? cs.primary.withValues(alpha: 0.12)
          : Colors.transparent,
      child: InkWell(
        key: itemKey,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: styles.body.copyWith(
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: styles.bodySmall.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

String _folderLabel(WorkspaceFolder folder) {
  final path = folder.path.replaceAll('\\', '/');
  final parts = path.split('/').where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return path.isEmpty ? folder.path : path;
  return parts.last;
}

Map<String, Object?> _filterCommonSchemaProps(Map<String, Object?> schema) {
  final props = schema['properties'];
  if (props is! Map) return schema;
  final filtered = <String, Object?>{
    for (final entry in props.entries)
      if (!_kCommonSchemaKeys.contains(entry.key.toString()))
        entry.key.toString(): entry.value,
  };
  return {...schema, 'properties': filtered};
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final it = iterator;
    if (!it.moveNext()) return null;
    return it.current;
  }
}
