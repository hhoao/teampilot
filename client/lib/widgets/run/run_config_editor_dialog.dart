import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/run_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/run/launch_configuration.dart';
import '../../models/run/launch_type_contribution.dart';
import '../../models/workspace_folder.dart';
import '../../services/run/launch_config_l10n.dart';
import '../../services/run/shell_script_launch_schema.dart';
import '../../theme/app_dialog_theme.dart';
import '../../theme/app_text_styles.dart';
import 'package:shared_ui/shared_ui.dart';
import 'launch_config_schema_form.dart';

const double _kEditorWidth = 560;
const _kCommonSchemaKeys = {'name', 'type', 'id', 'request'};

/// Opens the single-configuration editor dialog (create or edit).
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
    // ESC / barrier tap go through [PopScope] → [_onCancel] (dirty prompt).
    barrierDismissible: true,
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

/// Single-configuration editor (automation-editor style).
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
  final _formKey = GlobalKey<TpFormState>();
  OwnedLaunchConfiguration? _draft;
  OwnedLaunchConfiguration? _baseline;
  List<String> _formErrors = const [];
  var _closing = false;

  bool get _isDirty =>
      _draft != null && _baseline != null && _draft != _baseline;

  bool get _isCreating =>
      widget.createNew || (_draft?.configuration.id.isEmpty ?? false);

  @override
  void initState() {
    super.initState();
    final cubit = context.read<RunCubit>();
    if (widget.createNew) {
      final folders = cubit.folders;
      final target = widget.folder ??
          (folders.length == 1
              ? folders.single
              : folders.isNotEmpty
              ? folders.first
              : null);
      if (target != null) {
        _beginCreate(target);
      }
    } else if (widget.initial != null) {
      _selectOwned(widget.initial!);
    }
  }

  void _beginCreate(WorkspaceFolder folder) {
    final cubit = context.read<RunCubit>();
    final draft = cubit.createConfiguration(
      folder: folder,
      type: widget.initialType ?? ShellScriptLaunchSchema.typeName,
    );
    _draft = draft;
    _baseline = draft;
    _formErrors = const [];
  }

  void _selectOwned(OwnedLaunchConfiguration owned) {
    _draft = owned;
    _baseline = owned;
    _formErrors = const [];
  }

  void _onFolderChanged(WorkspaceFolder folder) {
    final draft = _draft;
    if (draft == null || draft.owner == folder) return;
    setState(() {
      _draft = OwnedLaunchConfiguration(
        owner: folder,
        configuration: draft.configuration,
      );
    });
  }

  void _onTypeChanged(String newType) {
    final draft = _draft;
    if (draft == null) return;
    final normalized = newType.trim();
    if (normalized.isEmpty || draft.configuration.type == normalized) return;

    final cubit = context.read<RunCubit>();
    final rebuilt = cubit.createConfiguration(
      folder: draft.owner,
      type: normalized,
    );
    final previous = draft.configuration;
    setState(() {
      _draft = OwnedLaunchConfiguration(
        owner: draft.owner,
        configuration: rebuilt.configuration.copyWith(
          id: previous.id,
          name: previous.name,
        ),
      );
      _formErrors = const [];
    });
  }

  Map<String, Object?> _schemaFor(String type) {
    final cubit = context.read<RunCubit>();
    final raw =
        cubit.schemaForType(type) ??
        (type == ShellScriptLaunchSchema.typeName
            ? ShellScriptLaunchSchema.configurationSchema
            : const <String, Object?>{});
    return _filterCommonSchemaProps(raw);
  }

  Future<_DirtyChoice?> _promptDirty() {
    final l10n = context.l10n;
    return showDialog<_DirtyChoice>(
      context: context,
      builder: (ctx) {
        return TpDialog(
          maxWidth: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TpDialogHeader(
                title: l10n.runDiscardChangesTitle,
                onClose: () => Navigator.of(ctx).pop(_DirtyChoice.cancel),
              ),
              const SizedBox(height: 12),
              Text(l10n.runDiscardChangesMessage),
              TpDialogActions(
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
    if (_closing) return;
    _closing = true;
    try {
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
    } finally {
      _closing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final media = MediaQuery.of(context);
    final dialogWidth = _kEditorWidth.clamp(
      0.0,
      media.size.width - kTpDialogInsetExtent,
    );
    final maxHeight = media.size.height * 0.85;
    final title = _isCreating
        ? l10n.runAddConfiguration
        : l10n.runEditConfigurations;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        unawaited(_onCancel());
      },
      child: TpDialog(
        maxWidth: dialogWidth,
        maxHeight: maxHeight,
        child: TpForm(
          key: _formKey,
          child: TpDialogPinnedLayout(
            header: TpDialogHeader(title: title, onClose: _onCancel),
            body: _buildBody(context),
            footer: TpDialogActions(
              children: [
                TextButton(
                  key: const Key('run-config-editor-cancel'),
                  onPressed: _onCancel,
                  child: Text(l10n.cancel),
                ),
                TextButton(
                  key: const Key('run-config-editor-apply'),
                  onPressed: _draft == null ? null : _onApply,
                  child: Text(l10n.runApply),
                ),
                FilledButton(
                  key: const Key('run-config-editor-ok'),
                  onPressed: _draft == null ? null : _onOk,
                  child: Text(l10n.ok),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final l10n = context.l10n;
    final styles = AppTextStyles.of(context);
    final cubit = context.read<RunCubit>();
    final draft = _draft;

    if (draft == null) {
      return Text(l10n.runSelectConfiguration, style: styles.sm);
    }

    final type = draft.configuration.type;
    final folders = cubit.folders;
    final showFolderPicker = _isCreating && folders.length > 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showFolderPicker) ...[
          TpFormField<String>(
            id: 'folder',
            initialValue: draft.owner.path,
            label: Text(l10n.runSelectFolder),
            layoutStyle: TpFormFieldLayoutStyle.inline,
            labelWidth: kLaunchConfigFormLabelWidth,
            builder: (state) {
              final selected = folders
                  .where((f) => f.path == state.value)
                  .firstOrNull;
              return TpSelect<WorkspaceFolder>(
                key: const Key('run-config-folder-dropdown'),
                items: folders,
                initialItem: selected ?? draft.owner,
                searchable: folders.length >= 8,
                decoration: TpSelectDecorations.themed(context),
                itemLabel: _folderLabel,
                onChanged: (folder) {
                  if (folder == null) return;
                  state.didChange(folder.path);
                  _onFolderChanged(folder);
                },
              );
            },
          ),
          const SizedBox(height: 12),
        ],
        TpFormField<String>(
          key: ValueKey<String>('run-config-type-$type'),
          id: 'type',
          initialValue: type,
          label: Text(l10n.runConfigurationType),
          layoutStyle: TpFormFieldLayoutStyle.inline,
          labelWidth: kLaunchConfigFormLabelWidth,
          builder: (state) {
            final targetId = draft.owner.targetId;
            final types = _orderedLaunchTypes(cubit.launchTypes)
                .where(
                  (item) =>
                      item.type == type ||
                      cubit.isTypeAvailableForTarget(
                        item.type,
                        targetId: targetId,
                      ),
                )
                .toList();
            final selected = types.where((t) => t.type == type).firstOrNull;
            return TpSelect<LaunchTypeContribution>(
              key: const Key('run-config-type-dropdown'),
              items: types,
              initialItem: selected,
              searchable: types.length >= 8,
              decoration: TpSelectDecorations.themed(context),
              itemLabel: (item) => localizeLaunchTypeLabel(l10n, item.type),
              onChanged: (item) {
                if (item == null) return;
                state.didChange(item.type);
                _onTypeChanged(item.type);
              },
            );
          },
        ),
        const SizedBox(height: 12),
        LaunchConfigSchemaForm(
          key: ValueKey<String>(
            '${draft.selectionKey}|$type|${draft.configuration.id}',
          ),
          value: draft.configuration,
          schema: _schemaFor(type),
          errors: _formErrors,
          onChanged: (next) {
            // Update draft without setState — rebuilding the form on every
            // keystroke resets caret position in the text fields.
            _draft = OwnedLaunchConfiguration(
              owner: draft.owner,
              configuration: next,
            );
          },
        ),
      ],
    );
  }
}

String _folderLabel(WorkspaceFolder folder) {
  final path = folder.path.replaceAll('\\', '/');
  final parts = path.split('/').where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return path.isEmpty ? folder.path : path;
  return parts.last;
}

List<LaunchTypeContribution> _orderedLaunchTypes(
  List<LaunchTypeContribution> types,
) {
  final builtIn = <LaunchTypeContribution>[];
  final extensions = <LaunchTypeContribution>[];
  for (final type in types) {
    if (type.type == ShellScriptLaunchSchema.typeName) {
      builtIn.add(type);
    } else {
      extensions.add(type);
    }
  }
  extensions.sort((a, b) => a.type.compareTo(b.type));
  return [...builtIn, ...extensions];
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
