import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';
import '../../widgets/app_toast/app_toast.dart';
import '../../widgets/tp_password_input.dart';
import 'package:uuid/uuid.dart';

import '../../cubits/ssh_profile_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/ssh_profile.dart';
import '../../models/vault_entry.dart';
import '../../repositories/ssh_credential_store.dart';
import '../../repositories/ssh_profile_repository.dart';
import '../../services/ssh/ssh_connection_failure.dart';
import '../../services/ssh/ssh_profile_connection_tester.dart';
import '../../services/vault/vault_service.dart';
import '../../services/terminal/terminal_transport_factory.dart';
import '../../services/workspace/workspace_pane_policy.dart';

/// Desktop settings: Orca-style modal for adding/editing an SSH target.
Future<void> showSshProfileFormDialog(
  BuildContext context, {
  SshProfile? profile,
}) {
  return showTpDialog<void>(
    context: context,
    presentation: TpDialogPresentation.page,
    mobileBreakpoint: WorkspacePanePolicy.narrowBreakpointWidth,
    maxWidth: 560,
    maxHeight: kTpDialogPageWideMaxHeight,
    builder: (ctx) => _SshProfileFormDialog(initialProfile: profile),
  );
}

class _SshProfileFormDialog extends StatefulWidget {
  const _SshProfileFormDialog({this.initialProfile});

  final SshProfile? initialProfile;

  @override
  State<_SshProfileFormDialog> createState() => _SshProfileFormDialogState();
}

class _SshProfileFormDialogState extends State<_SshProfileFormDialog> {
  final _formKey = GlobalKey<TpFormState>();
  late final TextEditingController _labelController;
  late final TextEditingController _hostController;
  late final TextEditingController _usernameController;
  late final TextEditingController _portController;
  late final TextEditingController _identityFileController;
  late final TextEditingController _passphraseController;
  late final TextEditingController _passwordController;
  var _saving = false;
  var _testing = false;
  List<VaultEntry> _vaultEntries = const [];
  String? _vaultEntryId;
  bool _saveToVault = false;

  bool get _isEditing => widget.initialProfile != null;

  @override
  void initState() {
    super.initState();
    final p = widget.initialProfile;
    _labelController = TextEditingController(text: p?.name ?? '');
    _hostController = TextEditingController(text: p?.host ?? '');
    _usernameController = TextEditingController(text: p?.username ?? '');
    _portController = TextEditingController(text: '${p?.port ?? 22}');
    _identityFileController = TextEditingController();
    _passphraseController = TextEditingController();
    _passwordController = TextEditingController();
    _vaultEntryId = p?.vaultEntryId;
    unawaited(_loadVaultEntries());
  }

  VaultEntry? get _selectedVaultEntry {
    final id = _vaultEntryId;
    if (id == null) return null;
    for (final entry in _vaultEntries) {
      if (entry.id == id) return entry;
    }
    return null;
  }

  Future<void> _loadVaultEntries() async {
    List<VaultEntry> entries;
    try {
      entries = await context.read<VaultService>().list();
    } on Object {
      entries = const [];
    }
    if (!mounted) return;
    setState(() {
      _vaultEntries = [
        for (final entry in entries)
          if (entry.type == VaultEntryType.sshPassword ||
              entry.type == VaultEntryType.sshPrivateKey)
            entry,
      ];
    });
  }

  @override
  void dispose() {
    _labelController.dispose();
    _hostController.dispose();
    _usernameController.dispose();
    _portController.dispose();
    _identityFileController.dispose();
    _passphraseController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  SshProfile _buildProfile() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final existing = widget.initialProfile;
    final host = _hostController.text.trim();
    final label = _labelController.text.trim();
    final username = _usernameController.text.trim();
    return SshProfile(
      id: existing?.id ?? const Uuid().v4(),
      name: label.isNotEmpty
          ? label
          : (username.isNotEmpty ? '$username@$host' : host),
      host: host,
      port: int.tryParse(_portController.text.trim()) ?? 22,
      username: username,
      authType: _usesPasswordAuth
          ? SshAuthType.password
          : SshAuthType.privateKey,
      vaultEntryId: _vaultEntryId,
      createdAt: existing == null || existing.createdAt == 0
          ? now
          : existing.createdAt,
      updatedAt: now,
    );
  }

  bool get _usesPasswordAuth {
    final selected = _selectedVaultEntry;
    if (selected != null) {
      return selected.type == VaultEntryType.sshPassword;
    }
    return _identityFileController.text.trim().isEmpty &&
        _passwordController.text.isNotEmpty;
  }

  Future<void> _browseIdentityFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      dialogTitle: context.l10n.sshProfileFormIdentityFileBrowse,
    );
    final path = result?.files.single.path;
    if (path != null && path.isNotEmpty && mounted) {
      setState(() => _identityFileController.text = path);
      _formKey.currentState?.setFieldValue('identityFile', path);
    }
  }

  Future<String?> _readIdentityFile() async {
    final path = _identityFileController.text.trim();
    if (path.isEmpty) return null;
    final missingMessage = context.l10n.sshProfileFormIdentityFileMissing;
    final file = File(path);
    if (!await file.exists()) {
      throw StateError(missingMessage);
    }
    return file.readAsString();
  }

  Future<void> _persistCredentials(SshProfile profile) async {
    // 已链接保险库条目的 profile 不再写钥匙串。
    if ((profile.vaultEntryId ?? '').isNotEmpty) return;
    final store = context.read<SshCredentialStore>();
    if (_usesPasswordAuth) {
      await store.savePassword(profile.id, _passwordController.text);
      return;
    }
    final identityPath = _identityFileController.text.trim();
    if (identityPath.isNotEmpty) {
      final pem = await _readIdentityFile();
      if (pem != null && pem.isNotEmpty) {
        await store.savePrivateKey(profile.id, pem);
      }
    }
    final passphrase = _passphraseController.text;
    if (passphrase.isNotEmpty) {
      await store.savePrivateKeyPassphrase(profile.id, passphrase);
    }
  }

  Future<SshProfile?> _save({required bool notify}) async {
    if (_formKey.currentState?.validate() != true) return null;
    final profile = _buildProfile();
    if (!_isEditing &&
        _vaultEntryId == null &&
        !_usesPasswordAuth &&
        _identityFileController.text.trim().isEmpty) {
      AppToast.show(
        context,
        message: context.l10n.sshProfileFormCredentialRequired,
        variant: TpToastVariant.warning,
      );
      return null;
    }
    await context.read<SshProfileRepository>().save(profile);
    var credentialsSaved = true;
    try {
      await _persistCredentials(profile);
    } on Object {
      credentialsSaved = false;
    }
    if (!mounted) return profile;
    if (!credentialsSaved) {
      AppToast.show(
        context,
        message: context.l10n.sshProfileFormCredentialSaveFailed,
        variant: TpToastVariant.warning,
      );
    }
    var migrated = false;
    if (credentialsSaved &&
        _saveToVault &&
        (profile.vaultEntryId ?? '').isEmpty) {
      final cubit = context.read<SshProfileCubit>();
      await cubit.load();
      migrated = (await cubit.migrateToVault(profile.id)) != null;
    }
    if (!mounted) return profile;
    if (notify) {
      if (!migrated) await context.read<SshProfileCubit>().load();
      if (mounted) Navigator.of(context).pop();
    }
    return profile;
  }

  Future<void> _testConnection() async {
    if (_formKey.currentState?.validate() != true) return;
    setState(() => _testing = true);
    final credentialStore = context.read<SshCredentialStore>();
    final sshClientFactory =
        context.read<TerminalTransportFactory>().sshClientFactory;
    try {
      final profile = _buildProfile();
      String? password;
      String? privateKey;
      String? passphrase;
      if ((_vaultEntryId ?? '').isNotEmpty) {
        final vault = context.read<VaultService>();
        if (_usesPasswordAuth) {
          password = await vault.readField(_vaultEntryId!, 'password');
        } else {
          privateKey = await vault.readField(_vaultEntryId!, 'privateKey');
          passphrase = await vault.readField(_vaultEntryId!, 'passphrase');
        }
      } else if (_usesPasswordAuth) {
        password = _passwordController.text;
      } else {
        privateKey = await _readIdentityFile();
        if ((privateKey == null || privateKey.isEmpty) && _isEditing) {
          privateKey = await credentialStore.loadPrivateKey(profile.id);
        }
        passphrase = _passphraseController.text.isEmpty
            ? await credentialStore.loadPrivateKeyPassphrase(profile.id)
            : _passphraseController.text;
      }
      await SshProfileConnectionTester(
        clientFactory: sshClientFactory,
      ).test(
        profile,
        password: password,
        privateKey: privateKey,
        privateKeyPassphrase: passphrase,
      );
      if (!mounted) return;
      AppToast.show(
        context,
        message: context.l10n.sshProfileTestSuccess,
        variant: TpToastVariant.success,
      );
    } on Object catch (error) {
      if (!mounted) return;
      AppToast.show(
        context,
        message: sshConnectionFailureUserMessage(error, context.l10n),
        variant: TpToastVariant.error,
      );
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _submit() async {
    setState(() => _saving = true);
    try {
      await _save(notify: true);
    } on Object catch (error) {
      if (!mounted) return;
      AppToast.show(
        context,
        message: error.toString(),
        variant: TpToastVariant.error,
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final busy = _saving || _testing;
    final narrow =
        MediaQuery.sizeOf(context).width <
        WorkspacePanePolicy.narrowBreakpointWidth;

    final formFields = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _TwoColRow(
          left: _field(
            id: 'label',
            controller: _labelController,
            label: l10n.sshProfileFormLabel,
            hint: l10n.sshProfileFormLabelHint,
          ),
          right: _field(
            id: 'host',
            controller: _hostController,
            label: l10n.sshProfileFormHost,
            hint: l10n.sshProfileFormHostHint,
            required: true,
            validator: (v) => v == null || v.trim().isEmpty
                ? l10n.sshProfileFormFieldRequired
                : null,
          ),
        ),
        const SizedBox(height: 12),
        _TwoColRow(
          left: _field(
            id: 'username',
            controller: _usernameController,
            label: l10n.sshProfileFormUsername,
            hint: l10n.sshProfileFormUsernameHint,
          ),
          right: _field(
            id: 'port',
            controller: _portController,
            label: l10n.sshProfileFormPort,
            keyboardType: TextInputType.number,
            validator: (v) {
              final port = int.tryParse(v ?? '');
              if (port == null || port < 1 || port > 65535) {
                return l10n.sshProfileFormPortInvalid;
              }
              return null;
            },
          ),
        ),
        const SizedBox(height: 16),
        if (_vaultEntries.isNotEmpty || _vaultEntryId != null) ...[
          TpSelect<String>(
            key: const Key('ssh-credential-source'),
            items: ['', ..._vaultEntries.map((entry) => entry.id)],
            initialItem: _vaultEntryId ?? '',
            itemLabel: (id) {
              if (id.isEmpty) return l10n.sshCredentialSourceKeychain;
              for (final entry in _vaultEntries) {
                if (entry.id == id) return entry.title;
              }
              return l10n.sshCredentialVaultDeleted;
            },
            onChanged: (id) => setState(() {
              _vaultEntryId = (id == null || id.isEmpty) ? null : id;
              if (_vaultEntryId != null) _saveToVault = false;
            }),
            decoration: TpSelectDecorations.themed(context),
            overlayHeight: kTpSelectDefaultOverlayHeight,
          ),
          const SizedBox(height: 12),
        ],
        _field(
          id: 'identityFile',
          controller: _identityFileController,
          label: l10n.sshProfileFormIdentityFile,
          hint: l10n.sshProfileFormIdentityFileHint,
          helper: l10n.sshProfileFormIdentityFileHelper,
          prefixIcon: Icons.key_outlined,
          suffix: IconButton(
            tooltip: l10n.sshProfileFormIdentityFileBrowse,
            onPressed: busy ? null : _browseIdentityFile,
            icon: const Icon(Icons.folder_open_outlined),
          ),
          onChanged: () => setState(() {}),
        ),
        const SizedBox(height: 12),
        _field(
          id: 'passphrase',
          controller: _passphraseController,
          label: l10n.sshProfileFormPassphrase,
          hint: l10n.sshProfileFormPassphraseHint,
          obscure: true,
        ),
        const SizedBox(height: 12),
        _field(
          id: 'password',
          controller: _passwordController,
          label: l10n.sshProfileFormPassword,
          hint: _isEditing
              ? l10n.sshProfileFormPasswordHintEdit
              : l10n.sshProfileFormPasswordHint,
          helper: l10n.sshProfileFormPasswordHelper,
          obscure: true,
          onChanged: () => setState(() {}),
        ),
        if (_vaultEntryId == null)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.sshSaveToVault),
            value: _saveToVault,
            onChanged: (value) =>
                setState(() => _saveToVault = value ?? false),
          ),
      ],
    );

    final actions = Padding(
      padding: _pageHostPadding(context),
      child: TpDialogActions(
        children: [
          TextButton(
            onPressed: busy ? null : () => Navigator.of(context).pop(),
            child: Text(l10n.cancel),
          ),
          OutlinedButton(
            onPressed: busy ? null : _testConnection,
            child: _testing
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(l10n.sshProfileTest),
          ),
          FilledButton(
            onPressed: busy ? null : _submit,
            child: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(_isEditing ? l10n.save : l10n.sshProfilesAddTarget),
          ),
        ],
      ),
    );

    return TpDialogPageShell(
      title: _isEditing
          ? l10n.sshProfileFormTitleEdit
          : l10n.sshProfileFormTitleNew,
      mobileBreakpoint: WorkspacePanePolicy.narrowBreakpointWidth,
      fillBody: false,
      onClose: busy ? null : () => Navigator.of(context).pop(),
      child: TpForm(
        key: _formKey,
        child: narrow
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      padding: _pageHostPaddingH(context),
                      child: formFields,
                    ),
                  ),
                  actions,
                ],
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Flexible(
                    fit: FlexFit.loose,
                    child: SingleChildScrollView(
                      child: formFields,
                    ),
                  ),
                  actions,
                ],
              ),
      ),
    );
  }

  Widget _field({
    required String id,
    required TextEditingController controller,
    required String label,
    String? hint,
    String? helper,
    IconData? prefixIcon,
    Widget? suffix,
    bool required = false,
    bool obscure = false,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
    VoidCallback? onChanged,
  }) {
    return TpFormField<String>(
      id: id,
      initialValue: controller.text,
      label: Text(required ? '$label *' : label),
      description: helper == null ? null : Text(helper),
      validator: validator,
      builder: (state) {
        final decoration = InputDecoration(
          hintText: hint,
          prefixIcon: prefixIcon == null ? null : Icon(prefixIcon),
          suffixIcon: suffix,
          // Border reflects error; message is shown by TpFormFieldLayout.
          errorText: state.hasError ? '' : null,
          errorStyle: const TextStyle(height: 0, fontSize: 0),
        );
        if (obscure) {
          return TpPasswordInput(
            controller: controller,
            focusNode: state.focusNode,
            keyboardType: keyboardType,
            onChanged: (value) {
              state.didChange(value);
              onChanged?.call();
            },
            decoration: decoration,
          );
        }
        return TextField(
          controller: controller,
          focusNode: state.focusNode,
          keyboardType: keyboardType,
          onChanged: (value) {
            state.didChange(value);
            onChanged?.call();
          },
          decoration: decoration,
        );
      },
    );
  }
}

class _TwoColRow extends StatelessWidget {
  const _TwoColRow({required this.left, required this.right});

  final Widget left;
  final Widget right;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: left),
        const SizedBox(width: 12),
        Expanded(child: right),
      ],
    );
  }
}

EdgeInsets _pageHostPadding(BuildContext context) {
  final narrow =
      MediaQuery.sizeOf(context).width <
      WorkspacePanePolicy.narrowBreakpointWidth;
  return narrow ? const EdgeInsets.fromLTRB(16, 0, 16, 16) : EdgeInsets.zero;
}

EdgeInsets _pageHostPaddingH(BuildContext context) {
  final narrow =
      MediaQuery.sizeOf(context).width <
      WorkspacePanePolicy.narrowBreakpointWidth;
  return narrow ? const EdgeInsets.fromLTRB(16, 0, 16, 0) : EdgeInsets.zero;
}
