import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:teampilot/theme/app_icon_sizes.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/mcp_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/mcp_server.dart';
import '../../theme/app_fonts.dart';
import '../../theme/app_text_styles.dart';
import '../../theme/workspace_surface_layers.dart';

/// Add/edit MCP server for the workspace detail pane (not full-screen).
class McpFormPage extends StatefulWidget {
  const McpFormPage({
    required this.onCancel,
    required this.onSaved,
    this.existing,
    super.key,
  });

  final McpServer? existing;
  final VoidCallback onCancel;
  final ValueChanged<bool> onSaved;

  @override
  State<McpFormPage> createState() => _McpFormPageState();
}

class _McpFormPageState extends State<McpFormPage> {
  late final TextEditingController _idCtrl;
  late final TextEditingController _nameCtrl;
  late final TextEditingController _descriptionCtrl;
  late final TextEditingController _tagsCtrl;
  late final TextEditingController _homepageCtrl;
  late final TextEditingController _docsCtrl;
  late final TextEditingController _jsonCtrl;

  bool _metadataExpanded = false;
  String? _jsonError;
  bool _saving = false;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _idCtrl = TextEditingController(text: existing?.id ?? '');
    _nameCtrl = TextEditingController(text: existing?.name ?? '');
    _descriptionCtrl = TextEditingController(text: existing?.description ?? '');
    _tagsCtrl = TextEditingController(text: existing?.tags.join(', ') ?? '');
    _homepageCtrl = TextEditingController(text: existing?.homepage ?? '');
    _docsCtrl = TextEditingController(text: existing?.docs ?? '');
    _jsonCtrl = TextEditingController(
      text: existing != null
          ? const JsonEncoder.withIndent('  ').convert(existing.server)
          : const JsonEncoder.withIndent('  ').convert({
              'type': 'stdio',
              'command': 'uvx',
              'args': ['mcp-server-fetch'],
            }),
    );
    _metadataExpanded = existing?.hasMetadata ?? false;
  }

  @override
  void dispose() {
    _idCtrl.dispose();
    _nameCtrl.dispose();
    _descriptionCtrl.dispose();
    _tagsCtrl.dispose();
    _homepageCtrl.dispose();
    _docsCtrl.dispose();
    _jsonCtrl.dispose();
    super.dispose();
  }

  void _formatJson() {
    try {
      final decoded = jsonDecode(_jsonCtrl.text);
      _jsonCtrl.text = const JsonEncoder.withIndent('  ').convert(decoded);
      setState(() => _jsonError = null);
    } catch (e) {
      setState(() => _jsonError = e.toString());
    }
  }

  Map<String, Object?>? _parseServerJson() {
    try {
      final decoded = jsonDecode(_jsonCtrl.text);
      if (decoded is! Map) {
        setState(() => _jsonError = 'JSON must be an object');
        return null;
      }
      setState(() => _jsonError = null);
      return decoded.cast<String, Object?>();
    } catch (e) {
      setState(() => _jsonError = e.toString());
      return null;
    }
  }

  Future<void> _save() async {
    final id = _idCtrl.text.trim();
    final name = _nameCtrl.text.trim();
    if (id.isEmpty || name.isEmpty) {
      setState(() => _jsonError = context.l10n.mcpFormRequiredFields);
      return;
    }
    final server = _parseServerJson();
    if (server == null) return;

    setState(() => _saving = true);
    final now = DateTime.now().millisecondsSinceEpoch;
    final existing = widget.existing;
    final record = McpServer(
      id: id,
      name: name,
      server: server,
      description: _descriptionCtrl.text.trim(),
      tags: parseMcpTags(_tagsCtrl.text),
      homepage: _homepageCtrl.text.trim(),
      docs: _docsCtrl.text.trim(),
      enabled: existing?.enabled ?? true,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
      source: existing?.source ?? McpServerSource.catalog,
      importedFrom: existing?.importedFrom,
    );

    final cubit = context.read<McpCubit>();
    final ok = await cubit.upsert(record);
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) {
      widget.onSaved(true);
      return;
    }
    final message = cubit.state.errorMessage;
    if (message != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textBase = isDark ? Colors.white : const Color(0xFF111827);

    return ListView(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 24),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  _isEditing ? l10n.mcpEdit : l10n.mcpAddTitle,
                  style: AppTextStyles.of(context).body.copyWith(
                    fontWeight: FontWeight.w800,
                    color: textBase,
                  ),
                ),
              ),
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(_isEditing ? Icons.save : Icons.add, size: context.appIconSizes.md),
                label: Text(_isEditing ? l10n.save : l10n.mcpFormSubmitAdd),
              ),
              IconButton(
                tooltip: l10n.cancel,
                onPressed: _saving ? null : widget.onCancel,
                icon: Icon(Icons.close),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _sectionCard(
          cs,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _idCtrl,
                enabled: !_isEditing,
                decoration: InputDecoration(
                  labelText: l10n.mcpFormIdLabel,
                  hintText: 'my-mcp-server',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _nameCtrl,
                decoration: InputDecoration(
                  labelText: l10n.mcpFormDisplayNameLabel,
                  hintText: l10n.mcpFormDisplayNameHint,
                ),
              ),
              const SizedBox(height: 8),
              InkWell(
                onTap: () =>
                    setState(() => _metadataExpanded = !_metadataExpanded),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      Text(
                        l10n.mcpFormMetadata,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const Spacer(),
                      Icon(
                        _metadataExpanded
                            ? Icons.expand_less
                            : Icons.expand_more,
                      ),
                    ],
                  ),
                ),
              ),
              if (_metadataExpanded) ...[
                const SizedBox(height: 8),
                TextField(
                  controller: _descriptionCtrl,
                  maxLines: 2,
                  decoration: InputDecoration(
                    labelText: l10n.mcpFormDescriptionLabel,
                    hintText: l10n.mcpFormDescriptionHint,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _tagsCtrl,
                  decoration: InputDecoration(
                    labelText: l10n.mcpFormTagsLabel,
                    hintText: l10n.mcpFormTagsHint,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _homepageCtrl,
                  keyboardType: TextInputType.url,
                  decoration: InputDecoration(
                    labelText: l10n.mcpFormHomepageLabel,
                    hintText: 'https://example.com',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _docsCtrl,
                  keyboardType: TextInputType.url,
                  decoration: InputDecoration(
                    labelText: l10n.mcpFormDocsLabel,
                    hintText: 'https://example.com/docs',
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        _sectionCard(
          cs,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text(
                    l10n.mcpFormJsonLabel,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: _formatJson,
                    child: Text(l10n.mcpFormFormatJson),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _jsonCtrl,
                maxLines: 12,
                style: appMonoTextStyle(context, height: 1.45),
                decoration: InputDecoration(
                  errorText: _jsonError,
                  filled: true,
                  fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.35),
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _sectionCard(ColorScheme cs, {required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: workspaceInsetDecoration(cs, radius: 12),
      child: child,
    );
  }
}
