import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/hook_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/hook_entry.dart';
import '../../models/team_config.dart';
import '../../services/hook/hook_repository.dart';
import '../../services/hook/import/hook_import_service.dart';

/// 打开 hook 导入对话框：CLI 选择 + JSON 粘贴 → 解析预览 → 勾选导入。
/// 返回 `true` 表示至少导入了一条。
Future<bool?> showHookImportDialog(BuildContext context) {
  return showTpDialog<bool>(
    context: context,
    builder: (_) => const HookImportDialog(),
  );
}

/// 两阶段导入对话框：
///
/// 1. 输入：选择目标 CLI + 粘贴 hooks JSON（settings.json hooks 段 / hooks.json /
///    片段），点「解析」。
/// 2. 预览：逐条勾选（脚本复制与不支持字段以徽标标注），点「导入」落库。
///
/// 解析失败（无可用条目）时停留在输入阶段并展示原始 warning 错误行。
class HookImportDialog extends StatefulWidget {
  const HookImportDialog({super.key});

  @override
  State<HookImportDialog> createState() => _HookImportDialogState();
}

class _HookImportDialogState extends State<HookImportDialog> {
  final _jsonController = TextEditingController();
  CliTool _cli = CliTool.claude;
  HookImportResult? _result;
  final _selected = <String>{};
  final _existingIds = <String>{};
  String? _errorMessage;
  var _importing = false;

  @override
  void dispose() {
    _jsonController.dispose();
    super.dispose();
  }

  Future<void> _parse() async {
    var result = await context.read<HookImportParser>().parseJson(
      cli: _cli,
      jsonText: _jsonController.text,
    );
    if (result.drafts.isEmpty && result.warnings.isEmpty) {
      // 空分组（如 `{"Stop": []}`）不产生任何 draft/warning → 静默无操作；
      // 显式给出一条错误行，避免"点了解析什么都没发生"。
      result = const HookImportResult(warnings: ['hook_import_no_hooks']);
    }
    if (!mounted) return;
    final existing = <String>{};
    for (final draft in result.drafts) {
      final saved = await context.read<HookRepository>().load(draft.definition.id);
      if (saved != null) existing.add(draft.definition.id);
    }
    if (!mounted) return;
    setState(() {
      _result = result;
      _existingIds
        ..clear()
        ..addAll(existing);
      _errorMessage = null;
      _selected
        ..clear()
        ..addAll(result.drafts.map((d) => d.definition.id));
    });
  }

  Future<void> _import() async {
    if (_importing) return;
    final drafts = (_result?.drafts ?? const [])
        .where((d) => _selected.contains(d.definition.id))
        .toList();
    if (drafts.isEmpty) return;
    setState(() => _importing = true);
    try {
      final count = await context.read<HookImportService>().import(drafts);
      if (!mounted) return;
      setState(() => _importing = false);
      if (count > 0) {
        await context.read<HookCubit>().load();
        if (!mounted) return;
        Navigator.of(context).pop(true);
      }
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _importing = false;
        _errorMessage = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final result = _result;
    // 预览仅当解析出至少一条可用 hook；解析失败时停留输入阶段展示错误。
    final hasPreview = result != null && result.drafts.isNotEmpty;
    return TpDialog(
      maxWidth: 640,
      maxHeight: 620,
      child: TpDialogPinnedLayout(
        header: TpDialogHeader(title: l10n.hookImport),
        body: hasPreview
            ? _buildPreview(context, result)
            : _buildInput(context, result),
        footer: TpDialogActions(
          children: [
            TextButton(
              key: const Key('hook-import-cancel'),
              onPressed: _importing
                  ? null
                  : () => Navigator.of(context).pop(false),
              child: Text(l10n.cancel),
            ),
            if (hasPreview)
              FilledButton(
                key: const Key('hook-import-confirm'),
                onPressed: _importing || _selected.isEmpty ? null : _import,
                child: Text(l10n.hookImportDone(_selected.length)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildInput(BuildContext context, HookImportResult? result) {
    final l10n = context.l10n;
    final errorText = _inputError(result, l10n);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TpFormField<CliTool>(
          initialValue: _cli,
          label: Text(l10n.hookImportCli),
          builder: (state) => TpSelect<CliTool>(
            key: const Key('hook-import-cli'),
            items: const [
              CliTool.claude,
              CliTool.flashskyai,
              CliTool.codex,
              CliTool.cursor,
            ],
            initialItem: _cli,
            searchable: false,
            itemLabel: (cli) => cli.name,
            onChanged: (value) {
              if (value == null) return;
              state.didChange(value);
              setState(() => _cli = value);
            },
          ),
        ),
        const SizedBox(height: 12),
        TpFormField<String>(
          initialValue: '',
          label: Text(l10n.hookImportJson),
          builder: (state) => TextField(
            key: const Key('hook-import-json'),
            controller: _jsonController,
            focusNode: state.focusNode,
            maxLines: 8,
            onChanged: state.didChange,
            decoration: InputDecoration(
              hintText: l10n.hookImportJsonHint,
              errorText: state.hasError ? '' : null,
              errorStyle: const TextStyle(height: 0, fontSize: 0),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.tonalIcon(
            key: const Key('hook-import-parse'),
            onPressed: _parse,
            icon: const Icon(Icons.manage_search),
            label: Text(l10n.hookImportParse),
          ),
        ),
        if (errorText != null) ...[
          const SizedBox(height: 8),
          Text(
            errorText,
            key: const Key('hook-import-error'),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
      ],
    );
  }

  /// 解析后无可用条目时的错误行：已知原始 warning 键映射为本地化文本
  /// （诊断后缀保留在分隔符之后），其余原样展示。
  String? _inputError(HookImportResult? result, AppLocalizations l10n) {
    if (result == null || result.drafts.isNotEmpty) return null;
    if (result.warnings.isEmpty) return null;
    return result.warnings.map((warning) {
      if (warning == 'hook_import_no_hooks') return l10n.hookImportNoHooks;
      if (warning.startsWith('hook_import_invalid_json')) {
        final separator = warning.indexOf(': ');
        final suffix = separator < 0 ? '' : warning.substring(separator + 2);
        return suffix.isEmpty
            ? l10n.hookImportInvalidJson
            : '${l10n.hookImportInvalidJson}: $suffix';
      }
      return warning;
    }).join('\n');
  }

  Widget _buildPreview(BuildContext context, HookImportResult result) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_errorMessage != null) ...[
          const SizedBox(height: 8),
          Text(
            _errorMessage!,
            key: const Key('hook-import-error'),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        for (final warning in result.warnings)
          if (!warning.startsWith('hook_import_invalid_json'))
            Text(
              warning,
              key: const Key('hook-import-warning'),
              style: TextStyle(
                color: Theme.of(context).colorScheme.tertiary,
                fontSize: 12,
              ),
            ),
        const SizedBox(height: 8),
        ListView(
          key: const Key('hook-import-preview'),
          shrinkWrap: true,
          children: [
            for (final draft in result.drafts)
              CheckboxListTile(
                value: _selected.contains(draft.definition.id),
                onChanged: (checked) {
                  setState(() {
                    if (checked == true) {
                      _selected.add(draft.definition.id);
                    } else {
                      _selected.remove(draft.definition.id);
                    }
                  });
                },
                title: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${draft.nativeEvent ?? draft.definition.event.name}'
                        '${draft.definition.matcher == null ? '' : ' · ${draft.definition.matcher}'}',
                      ),
                    ),
                    if (_existingIds.contains(draft.definition.id))
                      Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: Text(
                          l10n.hookImportOverwrite,
                          key: Key(
                            'hook-import-overwrite-${draft.definition.id}',
                          ),
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ),
                subtitle: Text(
                  _draftSubtitle(draft),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
        ),
      ],
    );
  }

  String _draftSubtitle(HookImportDraft draft) {
    final action = draft.definition.action;
    final base = action is HttpHookAction
        ? action.url
        : (action as CommandHookAction).command ?? '';
    final parts = <String>[
      base,
      if (draft.scriptFileName != null) '📄 ${draft.scriptFileName}',
      if (draft.unsupportedFields.isNotEmpty)
        '⚠ ${draft.unsupportedFields.join(', ')}',
    ];
    return parts.join(' · ');
  }
}
