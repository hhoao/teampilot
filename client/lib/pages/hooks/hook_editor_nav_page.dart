import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/hook_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/hook_definition.dart';
import '../../services/hook/hook_repository.dart';
import '../../utils/ui/app_keys.dart';
import '../../widgets/settings/workspace_section_host.dart';
import '../../widgets/settings/workspace_section_nav_item.dart';
import 'hook_editor_page.dart';

/// `/hooks/new` / `/hooks/:id` 路由宿主：读取既有定义后构造 [HookEditorPage]。
///
/// [HookEditorPage] 要求外部传入 [HookCubit]；这里复用 app 级 cubit
/// （[HookManagementPage] 同一实例），并
/// 从 [HookRepository] 预加载编辑目标（hook.json 不持久化脚本正文，脚本内容
/// 由页面经注入的 repository 读取）。
class HookEditorNavPage extends StatefulWidget {
  const HookEditorNavPage({this.hookId, super.key});

  /// 编辑目标的 hook id；null = 新建。
  final String? hookId;

  @override
  State<HookEditorNavPage> createState() => _HookEditorNavPageState();
}

class _HookEditorNavPageState extends State<HookEditorNavPage> {
  HookDefinition? _definition;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadDefinition();
  }

  Future<void> _loadDefinition() async {
    final id = widget.hookId;
    if (id == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final definition = await context.read<HookRepository>().load(id);
    if (!mounted) return;
    setState(() {
      _definition = definition;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return _Shell(
        title: context.l10n.hookEdit,
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (widget.hookId != null && _definition == null) {
      return _Shell(
        title: context.l10n.hookEdit,
        body: Center(child: Text(context.l10n.hooksNoInstalled)),
      );
    }
    return HookEditorPage(
      cubit: context.read<HookCubit>(),
      definition: _definition,
      repository: context.read<HookRepository>(),
    );
  }
}

class _Shell extends StatelessWidget {
  const _Shell({required this.title, required this.body});

  final String title;
  final Widget body;

  @override
  Widget build(BuildContext context) {
    return WorkspaceAdaptiveSectionPage(
      pageKey: AppKeys.hooksWorkspace,
      title: title,
      compactSectionTabs: true,
      items: [
        WorkspaceSectionNavItem(
          label: context.l10n.hookNavTitle,
          icon: Icons.bolt_outlined,
          selected: true,
          onSelect: () {},
        ),
      ],
      body: body,
    );
  }
}
