import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';
import '../widgets/app_toast/app_toast.dart';
import '../widgets/tp_password_input.dart';
import 'package:uuid/uuid.dart';

import '../l10n/l10n_extensions.dart';
import '../models/ssh_profile.dart';
import '../models/vault_entry.dart';
import '../repositories/ssh_credential_store.dart';
import '../repositories/ssh_profile_repository.dart';
import '../services/ssh/ssh_connection_failure.dart';
import '../services/ssh/ssh_profile_connection_tester.dart';
import '../services/vault/vault_service.dart';

class SshProfileSetupPage extends StatefulWidget {
  const SshProfileSetupPage({
    super.key,
    required this.profileRepository,
    required this.credentialStore,
    this.initialProfile,
    this.connectionTester,
    this.onProfileSaved,
    this.vaultService,
    this.embedded = false,
  });

  final SshProfileRepository profileRepository;
  final SshCredentialStore credentialStore;
  final SshProfile? initialProfile;
  final SshProfileConnectionTester? connectionTester;
  final VoidCallback? onProfileSaved;
  final VaultService? vaultService;

  /// When true, omits [Scaffold] so a parent (e.g. onboarding step) supplies
  /// chrome and scrolling.
  final bool embedded;

  @override
  State<SshProfileSetupPage> createState() => _SshProfileSetupPageState();
}

class _SshProfileSetupPageState extends State<SshProfileSetupPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _hostController = TextEditingController();
  final _portController = TextEditingController(text: '22');
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _privateKeyController = TextEditingController();
  final _passphraseController = TextEditingController();
  var _authType = SshAuthType.privateKey;
  var _obscurePassword = true;
  var _obscurePassphrase = true;
  var _saving = false;
  var _testing = false;
  List<VaultEntry> _vaultEntries = const [];
  String? _vaultEntryId;
  bool _saveToVault = false;

  bool get _isEditing => widget.initialProfile != null;

  @override
  void initState() {
    super.initState();
    final profile = widget.initialProfile;
    if (profile != null) {
      _nameController.text = profile.name;
      _hostController.text = profile.host;
      _portController.text = '${profile.port}';
      _usernameController.text = profile.username;
      _authType = profile.authType;
      _vaultEntryId = profile.vaultEntryId;
    }
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
    final vault = widget.vaultService;
    if (vault == null) return;
    List<VaultEntry> entries;
    try {
      entries = await vault.list();
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
    _nameController.dispose();
    _hostController.dispose();
    _portController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _privateKeyController.dispose();
    _passphraseController.dispose();
    super.dispose();
  }

  SshProfile _buildProfile() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final existing = widget.initialProfile;
    return SshProfile(
      id: existing?.id ?? const Uuid().v4(),
      name: _nameController.text.trim(),
      host: _hostController.text.trim(),
      port: int.tryParse(_portController.text.trim()) ?? 22,
      username: _usernameController.text.trim(),
      authType: _authType,
      vaultEntryId: _vaultEntryId,
      createdAt: existing == null || existing.createdAt == 0
          ? now
          : existing.createdAt,
      updatedAt: now,
    );
  }

  Future<SshProfile?> _saveProfile({required bool notify}) async {
    if (_formKey.currentState?.validate() != true) return null;
    final profile = _buildProfile();
    await widget.profileRepository.save(profile);

    if ((profile.vaultEntryId ?? '').isNotEmpty) {
      // 已链接保险库条目：凭据来自保险库，不再写钥匙串。
    } else if (_authType == SshAuthType.password) {
      if (_passwordController.text.isNotEmpty) {
        await widget.credentialStore.savePassword(
          profile.id,
          _passwordController.text,
        );
      }
    } else {
      if (_privateKeyController.text.isNotEmpty) {
        await widget.credentialStore.savePrivateKey(
          profile.id,
          _privateKeyController.text,
        );
      }
      if (_passphraseController.text.isNotEmpty) {
        await widget.credentialStore.savePrivateKeyPassphrase(
          profile.id,
          _passphraseController.text,
        );
      }
    }

    if (_saveToVault && (profile.vaultEntryId ?? '').isEmpty) {
      final migrated = await _migrateToVault(profile);
      if (migrated != null && mounted && notify) {
        widget.onProfileSaved?.call();
      }
      return migrated ?? profile;
    }

    if (mounted && notify) {
      widget.onProfileSaved?.call();
    }
    return profile;
  }

  Future<SshProfile?> _migrateToVault(SshProfile profile) async {
    final vault = widget.vaultService;
    if (vault == null) return null;
    final fields = <String, String>{
      'host': profile.host,
      'port': '${profile.port}',
      'username': profile.username,
    };
    if (_authType == SshAuthType.password) {
      if (_passwordController.text.isNotEmpty) {
        fields['password'] = _passwordController.text;
      }
    } else {
      if (_privateKeyController.text.isNotEmpty) {
        fields['privateKey'] = _privateKeyController.text;
      }
      if (_passphraseController.text.isNotEmpty) {
        fields['passphrase'] = _passphraseController.text;
      }
    }
    if (fields.length <= 3) return null;
    final entry = VaultEntry(
      id: const Uuid().v4(),
      type: _authType == SshAuthType.password
          ? VaultEntryType.sshPassword
          : VaultEntryType.sshPrivateKey,
      title: profile.name,
      fields: fields,
      revealable: _authType == SshAuthType.password,
    );
    await vault.upsert(entry);
    final updated = profile.copyWith(vaultEntryId: entry.id);
    await widget.profileRepository.save(updated);
    await widget.credentialStore.deleteAll(profile.id);
    return updated;
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await _saveProfile(notify: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _testConnection() async {
    final tester = widget.connectionTester;
    if (tester == null) return;
    if (_formKey.currentState?.validate() != true) return;
    setState(() => _testing = true);
    try {
      final profile = _buildProfile();
      final vault = widget.vaultService;
      final linkedId = _vaultEntryId;
      String? password;
      String? privateKey;
      String? passphrase;
      if (vault != null && linkedId != null) {
        if (_authType == SshAuthType.password) {
          password = await vault.readField(linkedId, 'password');
        } else {
          privateKey = await vault.readField(linkedId, 'privateKey');
          passphrase = await vault.readField(linkedId, 'passphrase');
        }
      } else {
        password =
            _authType == SshAuthType.password &&
                _passwordController.text.isNotEmpty
            ? _passwordController.text
            : null;
        privateKey =
            _authType == SshAuthType.privateKey &&
                _privateKeyController.text.isNotEmpty
            ? _privateKeyController.text
            : null;
        passphrase =
            _authType == SshAuthType.privateKey &&
                _passphraseController.text.isNotEmpty
            ? _passphraseController.text
            : null;
      }
      await tester.test(
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

  String? _required(String? value) {
    if (value == null || value.trim().isEmpty) return '必填';
    return null;
  }

  List<Widget> _buildFormFields() {
    return [
      TextFormField(
        controller: _nameController,
        decoration: const InputDecoration(
          labelText: 'Profile 名称',
          hintText: 'My Server',
        ),
        validator: _required,
      ),
      const SizedBox(height: 12),
      TextFormField(
        controller: _hostController,
        decoration: const InputDecoration(
          labelText: 'Host',
          hintText: '192.168.1.100',
        ),
        validator: _required,
      ),
      const SizedBox(height: 12),
      TextFormField(
        controller: _portController,
        decoration: const InputDecoration(labelText: 'Port'),
        keyboardType: TextInputType.number,
        validator: (v) {
          final port = int.tryParse(v ?? '');
          if (port == null || port < 1 || port > 65535) {
            return '端口无效';
          }
          return null;
        },
      ),
      const SizedBox(height: 12),
      TextFormField(
        controller: _usernameController,
        decoration: const InputDecoration(labelText: 'Username'),
        validator: _required,
      ),
      const SizedBox(height: 16),
      if (_vaultEntries.isNotEmpty || _vaultEntryId != null) ...[
        TpSelect<String>(
          key: const Key('ssh-credential-source'),
          items: ['', ..._vaultEntries.map((entry) => entry.id)],
          initialItem: _vaultEntryId ?? '',
          itemLabel: (id) {
            if (id.isEmpty) return context.l10n.sshCredentialSourceKeychain;
            for (final entry in _vaultEntries) {
              if (entry.id == id) return entry.title;
            }
            return context.l10n.sshCredentialVaultDeleted;
          },
          onChanged: (id) => setState(() {
            _vaultEntryId = (id == null || id.isEmpty) ? null : id;
            if (_vaultEntryId != null) {
              _saveToVault = false;
              _authType = _selectedVaultEntry?.type == VaultEntryType.sshPassword
                  ? SshAuthType.password
                  : SshAuthType.privateKey;
            }
          }),
          decoration: TpSelectDecorations.themed(context),
          overlayHeight: kTpSelectDefaultOverlayHeight,
        ),
        const SizedBox(height: 12),
      ],
      TpSegmentedPicker<SshAuthType>(
        selected: _authType,
        scrollable: false,
        segments: const [
          TpSegmentedOption(
            value: SshAuthType.privateKey,
            label: '私钥',
            icon: Icons.vpn_key_outlined,
          ),
          TpSegmentedOption(
            value: SshAuthType.password,
            label: '密码',
            icon: Icons.password_outlined,
          ),
        ],
        onChanged: (value) => setState(() => _authType = value),
      ),
      if (_vaultEntryId == null)
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(context.l10n.sshSaveToVault),
          value: _saveToVault,
          onChanged: (value) => setState(() => _saveToVault = value ?? false),
        ),
      const SizedBox(height: 12),
      if (_authType == SshAuthType.password)
        TextFormField(
          controller: _passwordController,
          decoration: InputDecoration(
            labelText: 'Password',
            hintText: _isEditing ? '留空则保留已保存密码' : null,
            suffixIcon: TpPasswordVisibilityToggle(
              key: const ValueKey('ssh-password-visibility-toggle'),
              obscured: _obscurePassword,
              onPressed: () =>
                  setState(() => _obscurePassword = !_obscurePassword),
            ),
          ),
          obscureText: _obscurePassword,
          validator: (v) => !_isEditing &&
                  _vaultEntryId == null &&
                  (v == null || v.trim().isEmpty)
              ? '必填'
              : null,
        )
      else ...[
        FormField<String>(
          initialValue: _privateKeyController.text,
          validator: (v) => !_isEditing &&
                  _vaultEntryId == null &&
                  (v == null || v.trim().isEmpty)
              ? '必填'
              : null,
          builder: (field) {
            final bodyStyle = TpTextStyles.of(context).md;
            final scheme = Theme.of(context).colorScheme;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TpTextarea(
                  controller: _privateKeyController,
                  minHeight: tpTextareaHeightForLines(bodyStyle, lines: 4),
                  maxHeight: tpTextareaHeightForLines(bodyStyle, lines: 8),
                  decoration: InputDecoration(
                    labelText: 'Private Key',
                    hintText: _isEditing
                        ? '留空则保留已保存私钥'
                        : 'Paste private key content',
                    // Border reflects error; message is shown below.
                    errorText: field.hasError ? '' : null,
                    errorStyle: const TextStyle(height: 0, fontSize: 0),
                  ),
                  onChanged: field.didChange,
                ),
                if (field.hasError)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      field.errorText!,
                      style: TextStyle(color: scheme.error, fontSize: 12),
                    ),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _passphraseController,
          decoration: InputDecoration(
            labelText: 'Private Key Passphrase',
            hintText: '可选',
            suffixIcon: TpPasswordVisibilityToggle(
              key: const ValueKey('ssh-passphrase-visibility-toggle'),
              obscured: _obscurePassphrase,
              onPressed: () =>
                  setState(() => _obscurePassphrase = !_obscurePassphrase),
            ),
          ),
          obscureText: _obscurePassphrase,
        ),
      ],
      const SizedBox(height: 24),
      if (widget.connectionTester != null) ...[
        OutlinedButton(
          onPressed: _saving || _testing ? null : _testConnection,
          child: _testing
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('测试连接'),
        ),
        const SizedBox(height: 12),
      ],
      ElevatedButton(
        onPressed: _saving ? null : _save,
        child: _saving
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Text('保存 Profile'),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final form = Form(
      key: _formKey,
      child: widget.embedded
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: _buildFormFields(),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: _buildFormFields(),
            ),
    );
    if (widget.embedded) return form;
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? '编辑 SSH Profile' : '新增 SSH Profile'),
      ),
      body: form,
    );
  }
}
