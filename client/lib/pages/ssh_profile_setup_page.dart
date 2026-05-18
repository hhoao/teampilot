import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../models/ssh_profile.dart';
import '../repositories/ssh_credential_store.dart';
import '../repositories/ssh_profile_repository.dart';
import '../services/ssh_profile_connection_tester.dart';

class SshProfileSetupPage extends StatefulWidget {
  const SshProfileSetupPage({
    super.key,
    required this.profileRepository,
    required this.credentialStore,
    this.initialProfile,
    this.connectionTester,
    this.onProfileSaved,
  });

  final SshProfileRepository profileRepository;
  final SshCredentialStore credentialStore;
  final SshProfile? initialProfile;
  final SshProfileConnectionTester? connectionTester;
  final VoidCallback? onProfileSaved;

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
  var _saving = false;
  var _testing = false;

  bool get _isEditing => widget.initialProfile != null;

  @override
  void initState() {
    super.initState();
    final profile = widget.initialProfile;
    if (profile == null) return;
    _nameController.text = profile.name;
    _hostController.text = profile.host;
    _portController.text = '${profile.port}';
    _usernameController.text = profile.username;
    _authType = profile.authType;
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

    if (_authType == SshAuthType.password) {
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

    if (mounted && notify) {
      widget.onProfileSaved?.call();
    }
    return profile;
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
      final password =
          _authType == SshAuthType.password &&
              _passwordController.text.isNotEmpty
          ? _passwordController.text
          : null;
      final privateKey =
          _authType == SshAuthType.privateKey &&
              _privateKeyController.text.isNotEmpty
          ? _privateKeyController.text
          : null;
      final passphrase =
          _authType == SshAuthType.privateKey &&
              _passphraseController.text.isNotEmpty
          ? _passphraseController.text
          : null;
      await tester.test(
        profile,
        password: password,
        privateKey: privateKey,
        privateKeyPassphrase: passphrase,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('SSH 连接测试成功')));
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('SSH 连接测试失败：$error')));
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  String? _required(String? value) {
    if (value == null || value.trim().isEmpty) return '必填';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? '编辑 SSH Profile' : '新增 SSH Profile'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
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
            SegmentedButton<SshAuthType>(
              segments: const [
                ButtonSegment(value: SshAuthType.privateKey, label: Text('私钥')),
                ButtonSegment(value: SshAuthType.password, label: Text('密码')),
              ],
              selected: {_authType},
              onSelectionChanged: (selected) {
                setState(() => _authType = selected.first);
              },
            ),
            const SizedBox(height: 12),
            if (_authType == SshAuthType.password)
              TextFormField(
                controller: _passwordController,
                decoration: InputDecoration(
                  labelText: 'Password',
                  hintText: _isEditing ? '留空则保留已保存密码' : null,
                ),
                obscureText: true,
                validator: (v) => !_isEditing && (v == null || v.trim().isEmpty)
                    ? '必填'
                    : null,
              )
            else ...[
              TextFormField(
                controller: _privateKeyController,
                decoration: InputDecoration(
                  labelText: 'Private Key',
                  hintText: _isEditing
                      ? '留空则保留已保存私钥'
                      : 'Paste private key content',
                ),
                maxLines: 4,
                validator: (v) => !_isEditing && (v == null || v.trim().isEmpty)
                    ? '必填'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _passphraseController,
                decoration: const InputDecoration(
                  labelText: 'Private Key Passphrase',
                  hintText: '可选',
                ),
                obscureText: true,
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
          ],
        ),
      ),
    );
  }
}
