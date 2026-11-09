import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/vault_cubit.dart';
import '../../l10n/app_localizations.dart';
import '../../models/vault_entry.dart';
import '../../models/vault_reference.dart';
import '../../services/vault/vault_service.dart';
import 'vault_entry_editor.dart';
import 'vault_entry_list.dart';
import 'vault_secret_reveal.dart';

Future<void> showVaultEntryDetail(BuildContext context, String entryId) {
  return showDialog<void>(
    context: context,
    builder: (_) => VaultEntryDetailDialog(entryId: entryId),
  );
}

class VaultEntryDetailDialog extends StatefulWidget {
  const VaultEntryDetailDialog({required this.entryId, super.key});

  final String entryId;

  @override
  State<VaultEntryDetailDialog> createState() => _VaultEntryDetailDialogState();
}

class _VaultEntryDetailDialogState extends State<VaultEntryDetailDialog> {
  List<VaultReference> _references = const [];

  @override
  void initState() {
    super.initState();
    _loadReferences();
  }

  Future<void> _loadReferences() async {
    final references = await context.read<VaultCubit>().referencesFor(
      widget.entryId,
    );
    if (mounted) setState(() => _references = references);
  }

  Future<void> _delete(VaultEntry entry) async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.vault.deleteTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_references.isNotEmpty) ...[
              Text(l10n.vault.deleteReferenced),
              for (final reference in _references) Text('• ${reference.label}'),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.vault.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.vault.deleteConfirm),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await context.read<VaultCubit>().remove(entry.id);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final entry = context.select<VaultCubit, VaultEntry?>(
      (cubit) => cubit.state.entries
          .where((candidate) => candidate.id == widget.entryId)
          .firstOrNull,
    );
    if (entry == null) {
      return AlertDialog(
        content: Text(l10n.vault.emptyTitle),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.vault.cancel),
          ),
        ],
      );
    }

    final fields = entry.fields.entries
        .where((field) => field.value.isNotEmpty)
        .toList();

    return AlertDialog(
      title: Text(entry.title),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(vaultTypeLabel(l10n, entry.type)),
              const SizedBox(height: 12),
              for (final field in fields) ...[
                VaultSecretField(
                  label: field.key,
                  value: field.value,
                  secret: entry.isSecretField(field.key),
                  revealable: entry.revealAllowed,
                  onAuthorizeReveal: () => authorizeVaultReveal(context),
                ),
                const SizedBox(height: 8),
              ],
              if (entry.notes.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(l10n.vault.entryNotes),
                Text(entry.notes),
              ],
              const SizedBox(height: 16),
              Text(
                l10n.vault.references,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              if (_references.isEmpty)
                Text(l10n.vault.noReferences)
              else
                for (final reference in _references)
                  Text('• ${reference.label}'),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => showVaultEntryEditor(context, existing: entry),
          child: Text(l10n.vault.save),
        ),
        TextButton(
          onPressed: () => _delete(entry),
          child: Text(l10n.vault.deleteConfirm),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.vault.cancel),
        ),
      ],
    );
  }
}

class VaultSecretField extends StatefulWidget {
  const VaultSecretField({
    required this.label,
    required this.value,
    required this.secret,
    this.revealable = true,
    this.revealDuration = const Duration(seconds: 30),
    this.onAuthorizeReveal,
    super.key,
  });

  final String label;
  final String value;
  final bool secret;
  final bool revealable;
  final Duration revealDuration;

  /// Re-authentication before the first reveal; true means allowed.
  final Future<bool> Function()? onAuthorizeReveal;

  @override
  State<VaultSecretField> createState() => _VaultSecretFieldState();
}

class _VaultSecretFieldState extends State<VaultSecretField> {
  Timer? _hideTimer;
  bool _revealed = false;

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  Future<void> _toggleReveal() async {
    if (!_revealed && widget.onAuthorizeReveal != null) {
      final allowed = await widget.onAuthorizeReveal!();
      if (!mounted || !allowed) return;
    }
    if (!mounted) return;
    setState(() => _revealed = !_revealed);
    _hideTimer?.cancel();
    if (_revealed) {
      _hideTimer = Timer(widget.revealDuration, () {
        if (mounted) setState(() => _revealed = false);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final visible = !widget.secret || _revealed;
    return Row(
      children: [
        Expanded(
          child: InputDecorator(
            decoration: InputDecoration(labelText: widget.label),
            child: SelectableText(visible ? widget.value : '••••••••'),
          ),
        ),
        if (widget.secret && widget.revealable)
          IconButton(
            tooltip: _revealed ? l10n.vault.hide : l10n.vault.reveal,
            icon: Icon(
              _revealed
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
            ),
            onPressed: _toggleReveal,
          ),
        if (widget.secret)
          IconButton(
            tooltip: l10n.vault.copy,
            icon: const Icon(Icons.copy_outlined),
            onPressed: () => copySecret(context, widget.value),
          ),
      ],
    );
  }
}

Future<void> copySecret(
  BuildContext context,
  String value, {
  Duration clearAfter = const Duration(seconds: 60),
}) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final l10n = context.l10n;
  final vault = context.read<VaultService>();
  if (vault.isEncrypted && !await authorizeVaultReveal(context)) return;
  await Clipboard.setData(ClipboardData(text: value));
  messenger?.showSnackBar(
    SnackBar(
      content: Text(l10n.vault.copied),
      duration: const Duration(seconds: 2),
    ),
  );
  Timer(clearAfter, () async {
    final current = await Clipboard.getData(Clipboard.kTextPlain);
    if (current?.text == value) {
      await Clipboard.setData(const ClipboardData(text: ''));
    }
  });
}
