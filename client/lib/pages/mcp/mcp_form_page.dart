import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../config/mcp_presets.dart';
import '../../cubits/mcp_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/mcp_server.dart';
import '../../theme/workspace_surface_layers.dart';

/// Full-screen add/edit form (cc-switch [McpFormModal] style).
class McpFormPage extends StatefulWidget {
  const McpFormPage({this.existing, super.key});

  final McpServer? existing;

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

  String? _selectedPresetId;
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
    if (existing != null) {
      _selectedPresetId = mcpPresetCustomId;
    }
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

  void _applyPreset(McpPreset preset) {
    setState(() {
      _selectedPresetId = preset.id;
      if (!_isEditing) {
        _idCtrl.text = preset.id;
      }
      _nameCtrl.text = preset.name;
      _descriptionCtrl.text = preset.description;
      _tagsCtrl.text = preset.tags.join(', ');
      _homepageCtrl.text = preset.homepage;
      _docsCtrl.text = preset.docs;
      _jsonCtrl.text = const JsonEncoder.withIndent('  ').convert(preset.server);
      _metadataExpanded = true;
      _jsonError = null;
    });
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
      Navigator.pop(context, true);
      return;
    }
    final message = cubit.state.errorMessage;
    if (message != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final presets = mcpPresets(descriptionFor: (id) => _presetDescription(l10n, id));

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(_isEditing ? l10n.mcpEdit : l10n.mcpAddTitle),
        actions: [
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.add, size: 18),
            label: Text(_isEditing ? l10n.save : l10n.mcpFormSubmitAdd),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          _sectionCard(
            cs,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  l10n.mcpFormTypeLabel,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ChoiceChip(
                      label: Text(l10n.mcpPresetCustom),
                      selected: _selectedPresetId == mcpPresetCustomId ||
                          _selectedPresetId == null,
                      onSelected: (_) => setState(() {
                        _selectedPresetId = mcpPresetCustomId;
                      }),
                    ),
                    for (final preset in presets)
                      ChoiceChip(
                        label: Text(preset.id),
                        selected: _selectedPresetId == preset.id,
                        onSelected: (_) => _applyPreset(preset),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
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
                  onTap: () => setState(() => _metadataExpanded = !_metadataExpanded),
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
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 13,
                    height: 1.45,
                  ),
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
      ),
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

String _presetDescription(dynamic l10n, String id) => switch (id) {
  'fetch' => l10n.mcpPresetDescFetch,
  'time' => l10n.mcpPresetDescTime,
  'memory' => l10n.mcpPresetDescMemory,
  'sequential-thinking' => l10n.mcpPresetDescSequentialThinking,
  'context7' => l10n.mcpPresetDescContext7,
  _ => '',
};
