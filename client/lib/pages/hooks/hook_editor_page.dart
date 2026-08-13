import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/hook_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/hook_definition.dart';
import '../../models/hook_entry.dart';
import '../../models/hook_event.dart';
import '../../models/team_config.dart';
import '../../services/hook/hook_repository.dart';
import '../../utils/ui/app_keys.dart';
import '../../widgets/settings/workspace_section_host.dart';
import '../../widgets/settings/workspace_section_nav_item.dart';

/// 新建/编辑 hook：name、description、event（带支持徽标）、matcher、action
/// 双模式（命令/脚本 + 脚本内容编辑）、policy（仅拦截事件）、timeoutSec、
/// env 键值；保存走 [HookCubit.upsert]；只读能力矩阵（事件 × 5 CLI）。
class HookEditorPage extends StatefulWidget {
  const HookEditorPage({
    required this.cubit,
    this.definition,
    this.repository,
    super.key,
  });

  final HookCubit cubit;

  /// 编辑目标；null = 新建。
  final HookDefinition? definition;

  /// 用于编辑时加载托管脚本内容（hook.json 不持久化脚本正文）。路由构造时
  /// 传入；为 null 时跳过脚本加载（widget 测试不需要）。
  final HookRepository? repository;

  @override
  State<HookEditorPage> createState() => _HookEditorPageState();
}

class _HookEditorPageState extends State<HookEditorPage> {
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

  Future<void> _save() async {
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
    final ok = await widget.cubit.upsert(definition, scripts: scripts);
    if (!mounted) return;
    if (ok && Navigator.of(context).canPop()) Navigator.of(context).pop();
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
    return WorkspaceAdaptiveSectionPage(
      pageKey: AppKeys.hooksWorkspace,
      title: widget.definition == null ? l10n.hookNew : l10n.hookEdit,
      compactSectionTabs: true,
      items: [
        WorkspaceSectionNavItem(
          label: l10n.hookNavTitle,
          icon: Icons.bolt_outlined,
          selected: true,
          onSelect: () {},
        ),
      ],
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            key: const Key('hook-name'),
            controller: _name,
            decoration: InputDecoration(labelText: l10n.hookName),
          ),
          TextField(
            controller: _description,
            decoration: InputDecoration(labelText: l10n.hookDescription),
          ),
          DropdownButtonFormField<HookEvent>(
            key: const Key('hook-event'),
            initialValue: _event,
            items: [
              for (final event in HookEvent.values)
                DropdownMenuItem(
                  value: event,
                  child: Text('${event.name}${_supportBadge(event)}'),
                ),
            ],
            onChanged: (value) {
              if (value == null) return;
              setState(() => _event = value);
            },
            decoration: InputDecoration(labelText: l10n.hookEvent),
          ),
          TextField(
            key: const Key('hook-matcher'),
            controller: _matcher,
            decoration: InputDecoration(labelText: l10n.hookMatcher),
          ),
          TextField(
            controller: _command,
            enabled: !_useScript,
            key: const Key('hook-command'),
            decoration: InputDecoration(labelText: l10n.hookActionCommand),
          ),
          SwitchListTile(
            key: const Key('hook-use-script'),
            title: Text(l10n.hookActionScript),
            value: _useScript,
            onChanged: (value) => setState(() => _useScript = value),
          ),
          if (_useScript)
            TextField(
              key: const Key('hook-script'),
              controller: _scriptContent,
              maxLines: 10,
              decoration: InputDecoration(
                labelText: 'hook.sh',
                alignLabelWithHint: true,
              ),
            ),
          if (_event.isIntercepting)
            DropdownButtonFormField<HookPolicy>(
              key: const Key('hook-policy'),
              initialValue: _policy,
              items: [
                for (final policy in HookPolicy.values)
                  DropdownMenuItem(value: policy, child: Text(policy.name)),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _policy = value);
              },
              decoration: InputDecoration(labelText: l10n.hookPolicy),
            ),
          TextField(
            controller: _timeout,
            key: const Key('hook-timeout'),
            decoration: InputDecoration(labelText: l10n.hookTimeoutSec),
          ),
          TextField(
            controller: _env,
            maxLines: 4,
            decoration: InputDecoration(labelText: l10n.hookEnv),
          ),
          const SizedBox(height: 16),
          _CapabilityMatrix(event: _event),
          const SizedBox(height: 16),
          TpButton(
            key: const Key('hook-save'),
            onPressed: _save,
            child: Text(l10n.hookSave),
          ),
        ],
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
        Text(l10n.hookCapabilityMatrix, key: const Key('hook-capability-matrix')),
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
