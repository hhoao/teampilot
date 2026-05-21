import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

/// Picks a directory path for a project (local picker or Android SSH path dialog).
Future<String?> pickProjectDirectoryPath(BuildContext context) async {
  if (Platform.isAndroid) {
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => const _RemoteProjectPathDialog(),
    );
  }
  return FilePicker.platform.getDirectoryPath();
}

class _RemoteProjectPathDialog extends StatefulWidget {
  const _RemoteProjectPathDialog();

  @override
  State<_RemoteProjectPathDialog> createState() =>
      _RemoteProjectPathDialogState();
}

class _RemoteProjectPathDialogState extends State<_RemoteProjectPathDialog> {
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
    return AlertDialog(
      title: const Text('Remote Project Path'),
      content: Form(
        key: _formKey,
        child: TextFormField(
          controller: _controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Path on SSH host',
            hintText: '~/work/project',
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
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('OK')),
      ],
    );
  }
}
