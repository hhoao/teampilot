import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:teampilot/theme/app_toast_theme.dart';
import 'package:teampilot/widgets/app_toast/app_toast.dart';
import 'package:uuid/uuid.dart';

import '../../cubits/ssh_profile_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/ssh_profile.dart';
import '../../repositories/ssh_credential_store.dart';
import '../../repositories/ssh_profile_repository.dart';
import '../../services/ssh/ssh_profile_connection_tester.dart';
import '../../services/terminal/terminal_transport_factory.dart';
import '../../widgets/app_dialog.dart';

/// Desktop settings: Orca-style modal for adding/editing an SSH target.
Future<void> showSshProfileFormDialog(
  BuildContext context, {
  SshProfile? profile,
}) {
  return showDialog<void>(
    context: context,
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
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _labelController;
  late final TextEditingController _hostController;
  late final TextEditingController _usernameController;
  late final TextEditingController _portController;
  late final TextEditingController _identityFileController;
  late final TextEditingController _passphraseController;
  late final TextEditingController _passwordController;
  var _saving = false;
  var _testing = false;

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
      authType: _usesPasswordAuth ? SshAuthType.password : SshAuthType.privateKey,
      createdAt: existing == null || existing.createdAt == 0
          ? now
          : existing.createdAt,
      updatedAt: now,
    );
  }

  bool get _usesPasswordAuth =>
      _identityFileController.text.trim().isEmpty &&
      _passwordController.text.isNotEmpty;

  Future<void> _browseIdentityFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      dialogTitle: context.l10n.sshProfileFormIdentityFileBrowse,
    );
    final path = result?.files.single.path;
    if (path != null && path.isNotEmpty && mounted) {
      setState(() => _identityFileController.text = path);
    }
  }

  Future<String?> _readIdentityFile() async {
    final path = _identityFileController.text.trim();
    if (path.isEmpty) return null;
    final file = File(path);
    if (!await file.exists()) {
      throw StateError(context.l10n.sshProfileFormIdentityFileMissing);
    }
    return file.readAsString();
  }

  Future<void> _persistCredentials(SshProfile profile) async {
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
        !_usesPasswordAuth &&
        _identityFileController.text.trim().isEmpty) {
      AppToast.show(
        context,
        message: context.l10n.sshProfileFormCredentialRequired,
        variant: AppToastVariant.warning,
      );
      return null;
    }
    await context.read<SshProfileRepository>().save(profile);
    await _persistCredentials(profile);
    if (notify && mounted) {
      await context.read<SshProfileCubit>().load();
      Navigator.of(context).pop();
    }
    return profile;
  }

  Future<void> _testConnection() async {
    if (_formKey.currentState?.validate() != true) return;
    setState(() => _testing = true);
    try {
      final profile = _buildProfile();
      String? password;
      String? privateKey;
      String? passphrase;
      if (_usesPasswordAuth) {
        password = _passwordController.text;
      } else {
        privateKey = await _readIdentityFile();
        if ((privateKey == null || privateKey.isEmpty) && _isEditing) {
          privateKey = await context
              .read<SshCredentialStore>()
              .loadPrivateKey(profile.id);
        }
        passphrase = _passphraseController.text.isEmpty
            ? await context
                .read<SshCredentialStore>()
                .loadPrivateKeyPassphrase(profile.id)
            : _passphraseController.text;
      }
      await SshProfileConnectionTester(
        clientFactory: context
            .read<TerminalTransportFactory>()
            .sshClientFactory,
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
        variant: AppToastVariant.success,
      );
    } on Object {
      if (!mounted) return;
      AppToast.show(
        context,
        message: context.l10n.sshProfileTestFailed,
        variant: AppToastVariant.error,
      );
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _submit() async {
    setState(() => _saving = true);
    try {
      await _save(notify: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final busy = _saving || _testing;

    return AppDialog(
      scrollable: true,
      maxWidth: 560,
      maxHeight: MediaQuery.sizeOf(context).height * 0.9,
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppDialogHeader(
              title: _isEditing
                  ? l10n.sshProfileFormTitleEdit
                  : l10n.sshProfileFormTitleNew,
              onClose: busy ? null : () => Navigator.of(context).pop(),
            ),
            const SizedBox(height: 16),
            _TwoColRow(
              left: _field(
                controller: _labelController,
                label: l10n.sshProfileFormLabel,
                hint: l10n.sshProfileFormLabelHint,
              ),
              right: _field(
                controller: _hostController,
                label: l10n.sshProfileFormHost,
                hint: l10n.sshProfileFormHostHint,
                required: true,
                validator: (v) =>
                    v == null || v.trim().isEmpty
                        ? l10n.sshProfileFormFieldRequired
                        : null,
              ),
            ),
            const SizedBox(height: 12),
            _TwoColRow(
              left: _field(
                controller: _usernameController,
                label: l10n.sshProfileFormUsername,
                hint: l10n.sshProfileFormUsernameHint,
              ),
              right: _field(
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
            _field(
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
            ),
            const SizedBox(height: 12),
            _field(
              controller: _passphraseController,
              label: l10n.sshProfileFormPassphrase,
              hint: l10n.sshProfileFormPassphraseHint,
              obscure: true,
            ),
            const SizedBox(height: 12),
            _field(
              controller: _passwordController,
              label: l10n.sshProfileFormPassword,
              hint: _isEditing
                  ? l10n.sshProfileFormPasswordHintEdit
                  : l10n.sshProfileFormPasswordHint,
              helper: l10n.sshProfileFormPasswordHelper,
              obscure: true,
            ),
            AppDialogActions(
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
                      : Text(
                          _isEditing
                              ? l10n.save
                              : l10n.sshProfilesAddTarget,
                        ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _field({
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
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType,
      validator: validator,
      decoration: InputDecoration(
        labelText: required ? '$label *' : label,
        hintText: hint,
        helperText: helper,
        prefixIcon: prefixIcon == null ? null : Icon(prefixIcon),
        suffixIcon: suffix,
      ),
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
