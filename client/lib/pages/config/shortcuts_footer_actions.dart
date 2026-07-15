import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/shortcut_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../services/commands/command_catalog.dart';
import '../../services/commands/key_chord.dart';
import '../../theme/app_toast_theme.dart';
import 'package:shared_ui/shared_ui.dart';
import '../../widgets/app_toast/app_toast.dart';

/// Footer row for the shortcuts settings page: reset-all, export (writes the
/// current overrides as `keybindings.json`), and import (validates + applies
/// with a "Replace all" confirm on conflicts — see [ShortcutCubit.importOverrides]).
class ShortcutsFooterActions extends StatelessWidget {
  const ShortcutsFooterActions({required this.state, super.key});

  final ShortcutState state;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          OutlinedButton(
            onPressed: () => _resetAll(context),
            child: Text(l10n.shortcutsResetAll),
          ),
          OutlinedButton(
            onPressed: () => _export(context, state),
            child: Text(l10n.shortcutsExport),
          ),
          OutlinedButton(
            onPressed: () => _import(context),
            child: Text(l10n.shortcutsImport),
          ),
        ],
      ),
    );
  }

  Future<void> _resetAll(BuildContext context) async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => TpDialog(
        maxWidth: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TpDialogHeader(
              title: l10n.shortcutsResetAllConfirmTitle,
              onClose: () => Navigator.of(ctx).pop(false),
            ),
            const SizedBox(height: 16),
            Text(l10n.shortcutsResetAllConfirmMessage),
            TpDialogActions(
              children: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: Text(l10n.cancel),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: Text(l10n.shortcutsResetAll),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await context.read<ShortcutCubit>().resetAll();
  }

  Future<void> _export(BuildContext context, ShortcutState state) async {
    final l10n = context.l10n;
    final path = await FilePicker.platform.saveFile(
      dialogTitle: l10n.shortcutsExport,
      fileName: 'keybindings.json',
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (path == null || !context.mounted) return;
    try {
      final payload = {
        'version': 1,
        'bindings': {
          for (final entry in state.overrides.entries)
            entry.key: entry.value.map((chord) => chord.toJson()).toList(),
        },
      };
      await File(path).writeAsString(jsonEncode(payload));
      if (context.mounted) {
        AppToast.show(context, message: l10n.shortcutsExportSuccess);
      }
    } on Object {
      if (context.mounted) {
        AppToast.show(
          context,
          message: l10n.shortcutsExportFailed,
          variant: AppToastVariant.error,
        );
      }
    }
  }

  Future<void> _import(BuildContext context) async {
    final l10n = context.l10n;
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (result == null || result.files.isEmpty) return;
    final path = result.files.single.path;
    if (path == null || !context.mounted) return;

    final parsed = _parseImportedBindings(await File(path).readAsString());
    if (parsed == null) {
      if (context.mounted) {
        AppToast.show(
          context,
          message: l10n.shortcutsImportInvalidFile,
          variant: AppToastVariant.error,
        );
      }
      return;
    }
    if (!context.mounted) return;

    final cubit = context.read<ShortcutCubit>();
    final firstAttempt = await cubit.importOverrides(parsed);
    if (!firstAttempt.applied && firstAttempt.conflicts.isNotEmpty) {
      if (!context.mounted) return;
      final replace = await _confirmImportConflicts(
        context,
        firstAttempt.conflicts.length,
      );
      if (replace != true) return;
      await cubit.importOverrides(parsed, replaceConflicts: true);
    }
    if (context.mounted) {
      AppToast.show(context, message: l10n.shortcutsImportSuccess);
    }
  }

  Future<bool?> _confirmImportConflicts(BuildContext context, int count) {
    final l10n = context.l10n;
    return showDialog<bool>(
      context: context,
      builder: (ctx) => TpDialog(
        maxWidth: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TpDialogHeader(
              title: l10n.shortcutsImportConflictTitle,
              onClose: () => Navigator.of(ctx).pop(false),
            ),
            const SizedBox(height: 16),
            Text(l10n.shortcutsImportConflictMessage(count)),
            TpDialogActions(
              children: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: Text(l10n.cancel),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: Text(l10n.shortcutsReplaceAction),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Parses a `keybindings.json`-shaped export into overrides, dropping
/// unknown command ids (same forward-compat rule as `KeybindingRepository`).
/// Returns `null` if [raw] isn't valid JSON in the expected shape.
Map<String, List<KeyChord>>? _parseImportedBindings(String raw) {
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return null;
    final bindingsRaw = decoded['bindings'];
    if (bindingsRaw is! Map) return null;

    final knownIds = {for (final def in CommandCatalog.v1) def.id};
    final result = <String, List<KeyChord>>{};
    for (final entry in bindingsRaw.entries) {
      final commandId = entry.key.toString();
      if (!knownIds.contains(commandId)) continue;
      final chordsRaw = entry.value;
      if (chordsRaw is! List) continue;
      result[commandId] = chordsRaw
          .whereType<Map>()
          .map((raw) => KeyChord.fromJson(raw.cast<String, dynamic>()))
          .toList(growable: false);
    }
    return result;
  } on Object {
    return null;
  }
}
