import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/hook_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/hook_definition.dart';
import '../../models/hook_entry.dart';
import '../../models/hook_event.dart';
import '../../models/team_config.dart';
import '../../services/hook/hook_repository.dart';

/// 打开新建/编辑 hook 对话框。返回 `true` = 保存成功；`false`/`null` = 取消。
Future<bool?> showHookEditorDialog(
  BuildContext context, {
  required HookCubit cubit,
  HookDefinition? definition,
  HookRepository? repository,
}) {
  return showTpDialog<bool>(
    context: context,
    builder: (_) => HookEditorDialog(
      cubit: cubit,
      definition: definition,
      repository: repository,
    ),
  );
}

/// 新建/编辑 hook 的对话框表单：name、description、event（带支持徽标）、
/// matcher、action 双模式（命令/脚本 + 脚本内容编辑）、policy（仅拦截事件）、
/// timeoutSec、env 键值；保存走 [HookCubit.upsert]；只读能力矩阵（事件 × 5 CLI）。
///
/// 表单遵循 app 标准表单样式：`TpForm` + `TpFormField`（label 走
/// [TpFormFieldLayout]，不复用 InputDecoration.labelText）；选择器用 [TpSelect]
/// 而非 Material `DropdownButtonFormField`。
class HookEditorDialog extends StatefulWidget {
  const HookEditorDialog({
    required this.cubit,
    this.definition,
    this.repository,
    super.key,
  });

  final HookCubit cubit;

  /// 编辑目标；null = 新建。
  final HookDefinition? definition;

  /// 用于编辑时加载托管脚本内容（hook.json 不持久化脚本正文）。为 null 时跳过
  /// 脚本加载（widget 测试不需要）。
  final HookRepository? repository;

  @override
  State<HookEditorDialog> createState() => _HookEditorDialogState();
}

class _HookEditorDialogState extends State<HookEditorDialog> {
  final _formKey = GlobalKey<TpFormState>();

  late final TextEditingController _name;
  late final TextEditingController _description;
  late final TextEditingController _matcher;
  late final TextEditingController _command;
  late final TextEditingController _scriptContent;
  late final TextEditingController _timeout;
  late final TextEditingController _env;

  late HookEvent _event;
  late HookPolicy _policy;
  bool _useScript = false;
  var _saving = false;

  @override
  void initState() {
    super.initState();
    final definition = widget.definition;
    _name = TextEditingController(text: definition?.name ?? '');
    _description = TextEditingController(text: definition?.description ?? '');
    _matcher = TextEditingController(text: definition?.matcher ?? '');
    final action = definition?.action;
    final command = action is CommandHookAction ? action.command ?? '' : '';
    _command = TextEditingController(text: command);
    _scriptContent = TextEditingController();
    _timeout = TextEditingController(
      text: definition?.timeoutSec?.toString() ?? '',
    );
    _env = TextEditingController(
      text: definition?.env.entries
              .map((e) => '${e.key}=${e.value}')
              .join('\n') ??
          '',
    );
    _event = definition?.event ?? HookEvent.stop;
    _policy = definition?.policy ?? HookPolicy.none;
    _useScript = action is CommandHookAction && action.command == null;
    _loadExistingScript();
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _matcher.dispose();
    _command.dispose();
    _scriptContent.dispose();
    _timeout.dispose();
    _env.dispose();
    super.dispose();
  }

  Future<void> _loadExistingScript() async {
    final definition = widget.definition;
    final repository = widget.repository;
    if (definition == null || repository == null) return;
    final action = definition.action;
    if (action is! CommandHookAction || action.command != null) return;
    final fileName = action.fileName ?? 'hook.sh';
    final content = await repository.readScript(definition.id, fileName);
    if (!mounted || content == null) return;
    setState(() => _scriptContent.text = content);
  }

  /// 标准表单文本字段：label 走 [TpFormFieldLayout]，TextField 只负责输入。
  Widget _textField({
    required Key fieldKey,
    required TextEditingController controller,
    required Widget label,
    String? hint,
    String? Function(String?)? validator,
    int maxLines = 1,
    bool enabled = true,
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
    final id = widget.definition?.id ?? _slugify(_name.text);
    if (id.isEmpty) return;
    final env = <String, String>{};
    for (final line in _env.text.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      final index = trimmed.indexOf('=');
      if (index <= 0) continue;
      env[trimmed.substring(0, index)] = trimmed.substring(index + 1);
    }
    final action = _useScript
        ? CommandHookAction.script(
            fileName: 'hook.sh',
            scriptContent: _scriptContent.text,
          )
        : CommandHookAction.raw(_command.text);
    final definition = HookDefinition(
      id: id,
      name: _name.text,
      description: _description.text,
      event: _event,
      matcher: _matcher.text.trim().isEmpty ? null : _matcher.text.trim(),
      action: action,
      policy: _event.isIntercepting ? _policy : HookPolicy.none,
      timeoutSec: int.tryParse(_timeout.text),
      env: env,
    );
    final scripts = _useScript
        ? {if (_scriptContent.text.isNotEmpty) 'hook.sh': _scriptContent.text}
        : const <String, String>{};
    setState(() => _saving = true);
    final ok = await widget.cubit.upsert(definition, scripts: scripts);
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) Navigator.of(context).pop(true);
  }

  String _slugify(String value) {
    final slug = value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-');
    return slug.replaceAll(RegExp(r'^-+|-+$'), '');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return TpDialog(
      maxWidth: 560,
      maxHeight: 680,
      child: TpDialogPinnedLayout(
        header: TpDialogHeader(
          title: widget.definition == null ? l10n.hookNew : l10n.hookEdit,
        ),
        body: TpForm(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _textField(
                fieldKey: const Key('hook-name'),
                controller: _name,
                label: Text(l10n.hookName),
                validator: (value) => (value == null || value.trim().isEmpty)
                    ? l10n.hookNameRequired
                    : null,
              ),
              const SizedBox(height: 12),
              _textField(
                fieldKey: const Key('hook-description'),
                controller: _description,
                label: Text(l10n.hookDescription),
              ),
              const SizedBox(height: 12),
              TpFormField<HookEvent>(
                initialValue: _event,
                label: Text(l10n.hookEvent),
                builder: (state) => TpSelect<HookEvent>(
                  key: const Key('hook-event'),
                  items: HookEvent.values,
                  initialItem: _event,
                  searchable: false,
                  itemLabel: (event) => '${event.name}${_supportBadge(event)}',
                  onChanged: (value) {
                    if (value == null) return;
                    state.didChange(value);
                    setState(() => _event = value);
                  },
                ),
              ),
              const SizedBox(height: 12),
              _textField(
                fieldKey: const Key('hook-matcher'),
                controller: _matcher,
                label: Text(l10n.hookMatcher),
              ),
              const SizedBox(height: 12),
              _textField(
                fieldKey: const Key('hook-command'),
                controller: _command,
                enabled: !_useScript,
                label: Text(l10n.hookActionCommand),
              ),
              SwitchListTile(
                key: const Key('hook-use-script'),
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.hookActionScript),
                value: _useScript,
                onChanged: (value) => setState(() => _useScript = value),
              ),
              if (_useScript)
                _textField(
                  fieldKey: const Key('hook-script'),
                  controller: _scriptContent,
                  label: Text('hook.sh'),
                  maxLines: 10,
                ),
              if (_event.isIntercepting) ...[
                const SizedBox(height: 12),
                TpFormField<HookPolicy>(
                  initialValue: _policy,
                  label: Text(l10n.hookPolicy),
                  builder: (state) => TpSelect<HookPolicy>(
                    key: const Key('hook-policy'),
                    items: HookPolicy.values,
                    initialItem: _policy,
                    searchable: false,
                    itemLabel: (policy) => policy.name,
                    onChanged: (value) {
                      if (value == null) return;
                      state.didChange(value);
                      setState(() => _policy = value);
                    },
                  ),
                ),
              ],
              const SizedBox(height: 12),
              _textField(
                fieldKey: const Key('hook-timeout'),
                controller: _timeout,
                label: Text(l10n.hookTimeoutSec),
              ),
              const SizedBox(height: 12),
              _textField(
                fieldKey: const Key('hook-env'),
                controller: _env,
                label: Text(l10n.hookEnv),
                maxLines: 4,
              ),
              const SizedBox(height: 16),
              _CapabilityMatrix(event: _event),
            ],
          ),
        ),
        footer: TpDialogActions(
          children: [
            TextButton(
              key: const Key('hook-cancel'),
              onPressed: _saving
                  ? null
                  : () => Navigator.of(context).pop(false),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              key: const Key('hook-save'),
              onPressed: _saving ? null : _save,
              child: Text(l10n.hookSave),
            ),
          ],
        ),
      ),
    );
  }

  String _supportBadge(HookEvent event) {
    final supported = CliTool.values
        .where((cli) => HookEventCapability.supports(event, cli))
        .length;
    return ' ($supported/5)';
  }
}

class _CapabilityMatrix extends StatelessWidget {
  const _CapabilityMatrix({required this.event});

  final HookEvent event;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.hookCapabilityMatrix,
          key: const Key('hook-capability-matrix'),
        ),
        const SizedBox(height: 4),
        for (final cli in CliTool.values)
          Builder(builder: (context) {
            final support = HookEventCapability.support(event, cli);
            final mark = !support.supported
                ? '✗'
                : support.approximate
                ? '≈'
                : '✓';
            return ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Text(mark),
              title: Text(cli.name),
              subtitle: support.nativeEvent == null
                  ? null
                  : Text(support.nativeEvent!),
            );
          }),
      ],
    );
  }
}
