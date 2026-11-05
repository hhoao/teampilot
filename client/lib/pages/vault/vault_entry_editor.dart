import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:uuid/uuid.dart';

import '../../cubits/vault_cubit.dart';
import '../../l10n/app_localizations.dart';
import '../../models/vault_entry.dart';
import '../../widgets/tp_password_input.dart';
import 'vault_entry_list.dart';

Future<void> showVaultEntryEditor(
  BuildContext context, {
  VaultEntry? existing,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => VaultEntryEditorDialog(existing: existing),
  );
}

class VaultEntryEditorDialog extends StatefulWidget {
  const VaultEntryEditorDialog({this.existing, super.key});

  final VaultEntry? existing;

  @override
  State<VaultEntryEditorDialog> createState() => _VaultEntryEditorDialogState();
}

class _VaultEntryEditorDialogState extends State<VaultEntryEditorDialog> {
  static const _uuid = Uuid();

  late VaultEntryType _type;
  late final TextEditingController _title;
  late final TextEditingController _tags;
  late final TextEditingController _notes;
  final _fields = <String, TextEditingController>{};
  late bool _favorite;
  late bool _revealable;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _type = existing?.type ?? VaultEntryType.sshPassword;
    _title = TextEditingController(text: existing?.title ?? '');
    _tags = TextEditingController(text: existing?.tags.join(', ') ?? '');
    _notes = TextEditingController(text: existing?.notes ?? '');
    _favorite = existing?.favorite ?? false;
    _revealable = existing?.revealable ?? true;
    _syncFields(existing?.fields ?? const {});
  }

  void _syncFields(Map<String, String> values) {
    final names = {..._type.defaultFields, ...values.keys};
    for (final name in names) {
      _fields.putIfAbsent(
        name,
        () => TextEditingController(text: values[name] ?? ''),
      );
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _tags.dispose();
    _notes.dispose();
    for (final controller in _fields.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final cubit = context.read<VaultCubit>();
    final title = _title.text.trim();
    if (title.isEmpty) return;
    final existing = widget.existing;
    final entry = VaultEntry(
      id: existing?.id ?? _uuid.v4(),
      type: _type,
      title: title,
      fields: {
        for (final field in _fields.entries)
          if (field.value.text.isNotEmpty) field.key: field.value.text,
      },
      tags: _tags.text
          .split(',')
          .map((tag) => tag.trim())
          .where((tag) => tag.isNotEmpty)
          .toList(),
      notes: _notes.text.trim(),
      favorite: _favorite,
      revealable: _revealable,
      createdAt: existing?.createdAt ?? 0,
      updatedAt: existing?.updatedAt ?? 0,
      extra: existing?.extra ?? const {},
    );
    await cubit.save(entry);
    if (mounted) await Navigator.of(context).maybePop();
    messenger?.showSnackBar(SnackBar(content: Text(l10n.vaultSave)));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(
        widget.existing == null ? l10n.vaultNewEntry : widget.existing!.title,
      ),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TpInput(
                key: const Key('vault-editor-title'),
                controller: _title,
                autofocus: true,
                decoration: InputDecoration(labelText: l10n.vaultEntryTitle),
              ),
              const SizedBox(height: 12),
              TpSelect<VaultEntryType>(
                items: VaultEntryType.values,
                initialItem: _type,
                itemLabel: (type) => vaultTypeLabel(l10n, type),
                onChanged: (type) {
                  if (type == null) return;
                  setState(() {
                    _type = type;
                    _syncFields(
                      {for (final f in _fields.entries) f.key: f.value.text},
                    );
                  });
                },
                decoration: TpSelectDecorations.themed(context),
                overlayHeight: kTpSelectDefaultOverlayHeight,
              ),
              const SizedBox(height: 12),
              for (final field in _fields.entries) ...[
                TpPasswordInput(
                  key: Key('vault-editor-field-${field.key}'),
                  controller: field.value,
                  decoration: InputDecoration(labelText: field.key),
                ),
                const SizedBox(height: 8),
              ],
              TpInput(
                controller: _tags,
                decoration: InputDecoration(labelText: l10n.vaultEntryTags),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _notes,
                maxLines: 3,
                decoration: InputDecoration(labelText: l10n.vaultEntryNotes),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.vaultEntryFavorite),
                value: _favorite,
                onChanged: (value) => setState(() => _favorite = value),
              ),
              if (_type != VaultEntryType.sshPrivateKey)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(l10n.vaultOnlyCopy),
                  value: !_revealable,
                  onChanged: (value) => setState(() => _revealable = !value),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.vaultCancel),
        ),
        FilledButton(
          key: const Key('vault-editor-save'),
          onPressed: _save,
          child: Text(l10n.vaultSave),
        ),
      ],
    );
  }
}
