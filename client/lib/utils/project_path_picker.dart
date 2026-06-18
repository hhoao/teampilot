import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../widgets/app_dialog.dart';

/// Picks a directory path for a workspace (local picker or Android SSH path dialog).
Future<String?> pickWorkspaceDirectoryPath(BuildContext context) async {
  if (Platform.isAndroid) {
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => const _RemoteWorkspacePathDialog(),
    );
  }
  return FilePicker.platform.getDirectoryPath();
}

class _RemoteWorkspacePathDialog extends StatefulWidget {
  const _RemoteWorkspacePathDialog();

  @override
  State<_RemoteWorkspacePathDialog> createState() =>
      _RemoteWorkspacePathDialogState();
}

class _RemoteWorkspacePathDialogState extends State<_RemoteWorkspacePathDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: '~/');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState?.validate() != true) return;
    Navigator.of(context).pop(_controller.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      maxWidth: 480,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AppDialogHeader(title: 'Remote Workspace Path'),
          const SizedBox(height: 16),
          Form(
            key: _formKey,
            child: TextFormField(
              controller: _controller,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Path on SSH host',
                hintText: '~/work/workspace',
              ),
              textInputAction: TextInputAction.done,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Required';
                }
                return null;
              },
              onFieldSubmitted: (_) => _submit(),
            ),
          ),
          AppDialogActions(
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(onPressed: _submit, child: const Text('OK')),
            ],
          ),
        ],
      ),
    );
  }
}
