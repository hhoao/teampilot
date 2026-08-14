import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';
import '../../widgets/app_toast/app_toast.dart';

import '../../cubits/mcp_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/mcp_server.dart';
import '../../theme/app_fonts.dart';

/// 打开新建/编辑 MCP server 对话框。返回 `true` = 保存成功；`false`/`null` = 取消。
Future<bool?> showMcpEditorDialog(
  BuildContext context, {
  required McpCubit cubit,
  McpServer? existing,
}) {
  return showTpDialog<bool>(
    context: context,
    builder: (_) => McpEditorDialog(cubit: cubit, existing: existing),
  );
}

/// 新建/编辑 MCP server 的对话框表单：id、name、可展开 metadata
/// （description/tags/homepage/docs）、server JSON；保存走 [McpCubit.upsert]。
class McpEditorDialog extends StatefulWidget {
  const McpEditorDialog({
    required this.cubit,
    this.existing,
    super.key,
  });

  final McpCubit cubit;

  /// 编辑目标；null = 新建。
  final McpServer? existing;

  @override
  State<McpEditorDialog> createState() => _McpEditorDialogState();
}

class _McpEditorDialogState extends State<McpEditorDialog> {
  final _formKey = GlobalKey<TpFormState>();

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

  Widget _textField({
    required Key fieldKey,
    required TextEditingController controller,
    required Widget label,
    String? hint,
    String? Function(String?)? validator,
    bool enabled = true,
    int maxLines = 1,
    TextInputType? keyboardType,
  }) {
    return TpFormField<String>(
      initialValue: controller.text,
      label: label,
      validator: validator,
      builder: (state) {
        return TextField(
          key: fieldKey,
          controller: controller,
          focusNode: state.focusNode,
          enabled: enabled,
          maxLines: maxLines,
          keyboardType: keyboardType,
          onChanged: state.didChange,
          decoration: InputDecoration(
            hintText: hint,
            errorText: state.hasError ? '' : null,
            errorStyle: const TextStyle(height: 0, fontSize: 0),
          ),
        );
      },
    );
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final server = _parseServerJson();
    if (server == null) return;

    setState(() => _saving = true);
    final now = DateTime.now().millisecondsSinceEpoch;
    final existing = widget.existing;
    final record = McpServer(
      id: _idCtrl.text.trim(),
      name: _nameCtrl.text.trim(),
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

    final ok = await widget.cubit.upsert(record);
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) {
      Navigator.of(context).pop(true);
      return;
    }
    final message = widget.cubit.state.errorMessage;
    if (message != null) {
      AppToast.show(context, message: message, variant: TpToastVariant.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;

    return TpDialog(
      maxWidth: 560,
      maxHeight: 680,
      child: TpDialogPinnedLayout(
        header: TpDialogHeader(
          title: _isEditing ? l10n.mcpEdit : l10n.mcpAddTitle,
        ),
        body: TpForm(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _textField(
                fieldKey: const Key('mcp-id'),
                controller: _idCtrl,
                enabled: !_isEditing,
                label: Text(l10n.mcpFormIdLabel),
                hint: 'my-mcp-server',
                validator: (value) => (value == null || value.trim().isEmpty)
                    ? l10n.mcpFormRequiredFields
                    : null,
              ),
              const SizedBox(height: 12),
              _textField(
                fieldKey: const Key('mcp-name'),
                controller: _nameCtrl,
                label: Text(l10n.mcpFormDisplayNameLabel),
                hint: l10n.mcpFormDisplayNameHint,
                validator: (value) => (value == null || value.trim().isEmpty)
                    ? l10n.mcpFormRequiredFields
                    : null,
              ),
              const SizedBox(height: 8),
              TpHover(
                onTap: () =>
                    setState(() => _metadataExpanded = !_metadataExpanded),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      Text(
                        l10n.mcpFormMetadata,
                        style: TpTextStyles.of(context).mdSemiboldTightSnug,
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
                _textField(
                  fieldKey: const Key('mcp-desc'),
                  controller: _descriptionCtrl,
                  label: Text(l10n.mcpFormDescriptionLabel),
                  hint: l10n.mcpFormDescriptionHint,
                  maxLines: 2,
                ),
                const SizedBox(height: 12),
                _textField(
                  fieldKey: const Key('mcp-tags'),
                  controller: _tagsCtrl,
                  label: Text(l10n.mcpFormTagsLabel),
                  hint: l10n.mcpFormTagsHint,
                ),
                const SizedBox(height: 12),
                _textField(
                  fieldKey: const Key('mcp-homepage'),
                  controller: _homepageCtrl,
                  keyboardType: TextInputType.url,
                  label: Text(l10n.mcpFormHomepageLabel),
                  hint: 'https://example.com',
                ),
                const SizedBox(height: 12),
                _textField(
                  fieldKey: const Key('mcp-docs'),
                  controller: _docsCtrl,
                  keyboardType: TextInputType.url,
                  label: Text(l10n.mcpFormDocsLabel),
                  hint: 'https://example.com/docs',
                ),
              ],
              const SizedBox(height: 16),
              Row(
                children: [
                  Text(
                    l10n.mcpFormJsonLabel,
                    style: TpTextStyles.of(context).mdSemiboldTightSnug,
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: _formatJson,
                    child: Text(l10n.mcpFormFormatJson),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Builder(
                builder: (context) {
                  final mono = appMonoTextStyle(context, height: 1.45);
                  return TpTextarea(
                    key: const Key('mcp-json'),
                    controller: _jsonCtrl,
                    minHeight: tpTextareaHeightForLines(mono, lines: 8),
                    maxHeight: tpTextareaHeightForLines(mono, lines: 12),
                    style: mono,
                    decoration: InputDecoration(
                      errorText: _jsonError,
                      filled: true,
                      fillColor: cs.surfaceContainerHighest.withValues(
                        alpha: 0.35,
                      ),
                      border: const OutlineInputBorder(),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
        footer: TpDialogActions(
          children: [
            TextButton(
              key: const Key('mcp-cancel'),
              onPressed: _saving
                  ? null
                  : () => Navigator.of(context).pop(false),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              key: const Key('mcp-save'),
              onPressed: _saving ? null : _save,
              child: Text(_isEditing ? l10n.save : l10n.mcpFormSubmitAdd),
            ),
          ],
        ),
      ),
    );
  }
}
