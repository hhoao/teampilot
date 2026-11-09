import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/git_graph_actions_controller.dart';
import '../../cubits/git_graph_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/git_compare.dart';
import '../../models/git_graph.dart';
import 'git_graph_compare_targets.dart';

/// 行级右键 / 长按菜单：checkout 本地分支或该提交（分离 HEAD）、重命名 / 删除 /
/// 合并本地分支、删除 / 推送标签、在此建分支 / 标签、cherry-pick、revert、
/// reset（hard 需输入当前分支名确认）与复制哈希 / 说明。
/// 所有写操作经 [GitGraphActionsController]；成败反馈由状态栏错误区呈现。
Future<void> showCommitContextMenu(
  BuildContext context,
  Offset position,
  GitCommitRow row,
  GitGraphActionsController actions,
  GitGraphState state, {
  required String workspaceId,
  required String repoRoot,
}) async {
  String? localBranch;
  String? tagName;
  for (final ref in row.refs) {
    if (ref.kind == GitRefDecorationKind.localBranch && localBranch == null) {
      localBranch = ref.name;
    }
    if (ref.kind == GitRefDecorationKind.tag && tagName == null) {
      tagName = ref.name;
    }
  }
  final l10n = context.l10n;
  final choice = await showTpActionMenuFromSpecs<String>(
    context: context,
    globalPosition: position,
    specs: _menuSpecs(l10n, localBranch, tagName),
  );
  if (choice == null || !context.mounted) return;
  switch (choice) {
    case 'checkout':
      if (localBranch != null) await actions.checkoutBranch(localBranch);
    case 'rename-branch':
      final newName = await showRenameBranchDialog(context, localBranch!);
      if (newName == null || newName.isEmpty || !context.mounted) return;
      await actions.renameBranch(localBranch, newName);
    case 'delete-branch':
      final confirmed = await confirmDangerAction(
        context,
        title: l10n.gitGraph.deleteBranchTitle,
        body: l10n.gitGraph.deleteBranchConfirmBody(name: localBranch!),
      );
      if (confirmed && context.mounted) await actions.deleteBranch(localBranch);
    case 'merge-branch':
      await actions.mergeIntoCurrent(localBranch!);
    case 'checkout-commit':
      final confirmed = await confirmDangerAction(
        context,
        title: l10n.gitGraph.checkoutCommit,
        body: l10n.gitGraph.checkoutCommitConfirmBody(hash: row.hash),
      );
      if (confirmed && context.mounted) await actions.checkoutCommit(row.hash);
    case 'create-branch':
      final name = await _promptBranchName(context);
      if (name == null || name.isEmpty || !context.mounted) return;
      await actions.createBranch(name, atHash: row.hash);
    case 'create-tag':
      final tag = await _promptTagName(context);
      if (tag == null || tag.$1.isEmpty || !context.mounted) return;
      await actions.createTag(
        tag.$1,
        at: row.hash,
        message: tag.$2.isEmpty ? null : tag.$2,
      );
    case 'delete-tag':
      final confirmed = await confirmDangerAction(
        context,
        title: l10n.gitGraph.deleteTagTitle,
        body: l10n.gitGraph.deleteTagConfirmBody(name: tagName!),
      );
      if (confirmed && context.mounted) await actions.deleteTag(tagName);
    case 'push-tag':
      await actions.pushTag(tagName!);
    case 'cherry-pick':
      await actions.cherryPick(row.hash);
    case 'revert':
      final confirmed = await confirmDangerAction(
        context,
        title: l10n.gitGraph.revert,
        body: l10n.gitGraph.revertConfirmBody(hash: row.hash),
      );
      if (confirmed && context.mounted) await actions.revert(row.hash);
    case 'reset-hard':
      final branch = state.currentBranch;
      final confirmed = await confirmDangerAction(
        context,
        title: l10n.gitGraph.resetHard,
        body: l10n.gitGraph.resetHardConfirmBody(branch: branch),
        typeToConfirm: branch,
      );
      if (confirmed && context.mounted) {
        await actions.resetTo(row.hash, mode: GitResetMode.hard);
      }
    case 'reset-soft':
      await actions.resetTo(row.hash, mode: GitResetMode.soft);
    case 'reset-mixed':
      await actions.resetTo(row.hash, mode: GitResetMode.mixed);
    case 'compare':
      await showGitCompareTargetMenu(
        context: context,
        globalPosition: position,
        workspaceId: workspaceId,
        state: state,
        source: GitCompareRef(row.hash),
      );
    case 'copy-hash':
      await _copyAndNotify(
        context,
        text: row.hash,
        message: l10n.gitGraph.hashCopied,
      );
    case 'copy-subject':
      await _copyAndNotify(
        context,
        text: row.subject,
        message: l10n.gitGraph.subjectCopied,
      );
  }
}

/// 平铺动作规格；reset 三档以禁用组头 + 扁平条目呈现（hard 保留输入确认）。
List<TpActionMenuSpec> _menuSpecs(
  AppLocalizations l10n,
  String? localBranch,
  String? tagName,
) => [
  if (localBranch != null) ...[
    TpActionMenuSpec.item(
      value: 'checkout',
      icon: Icons.check_circle_outline,
      label: l10n.gitGraph.checkoutBranch(branch: localBranch),
    ),
    TpActionMenuSpec.item(
      value: 'rename-branch',
      icon: Icons.drive_file_rename_outline,
      label: l10n.gitGraph.renameBranch,
    ),
    TpActionMenuSpec.item(
      value: 'delete-branch',
      icon: Icons.delete_outline,
      label: l10n.gitGraph.deleteBranch(name: localBranch),
      destructive: true,
    ),
    TpActionMenuSpec.item(
      value: 'merge-branch',
      icon: Icons.merge_type,
      label: l10n.gitGraph.mergeIntoCurrent(branch: localBranch),
    ),
  ],
  TpActionMenuSpec.item(
    value: 'create-branch',
    icon: Icons.fork_right,
    label: l10n.gitGraph.createBranchHere,
  ),
  TpActionMenuSpec.item(
    value: 'create-tag',
    icon: Icons.sell_outlined,
    label: l10n.gitGraph.createTagHere,
  ),
  TpActionMenuSpec.item(
    value: 'checkout-commit',
    icon: Icons.commit,
    label: l10n.gitGraph.checkoutCommit,
  ),
  if (tagName != null) ...[
    TpActionMenuSpec.item(
      value: 'push-tag',
      icon: Icons.cloud_upload_outlined,
      label: l10n.gitGraph.pushTag(name: tagName),
    ),
    TpActionMenuSpec.item(
      value: 'delete-tag',
      icon: Icons.delete_outline,
      label: l10n.gitGraph.deleteTag(name: tagName),
      destructive: true,
    ),
  ],
  TpActionMenuSpec.item(
    value: 'cherry-pick',
    icon: Icons.playlist_add,
    label: l10n.gitGraph.cherryPick,
  ),
  TpActionMenuSpec.item(
    value: 'revert',
    icon: Icons.undo,
    label: l10n.gitGraph.revert,
  ),
  TpActionMenuSpec.item(
    icon: Icons.restart_alt,
    label: l10n.gitGraph.reset,
    enabled: false,
  ),
  TpActionMenuSpec.item(
    value: 'reset-soft',
    icon: Icons.restart_alt,
    label: l10n.gitGraph.resetSoft,
  ),
  TpActionMenuSpec.item(
    value: 'reset-mixed',
    icon: Icons.restart_alt,
    label: l10n.gitGraph.resetMixed,
  ),
  TpActionMenuSpec.item(
    value: 'reset-hard',
    icon: Icons.restart_alt,
    label: l10n.gitGraph.resetHard,
    destructive: true,
  ),
  const TpActionMenuSpec.divider(),
  TpActionMenuSpec.item(
    value: 'compare',
    icon: Icons.difference_outlined,
    label: l10n.gitGraph.compareWith,
  ),
  TpActionMenuSpec.item(
    value: 'copy-hash',
    icon: Icons.copy,
    label: l10n.gitGraph.copyHash,
  ),
  TpActionMenuSpec.item(
    value: 'copy-subject',
    icon: Icons.subject,
    label: l10n.gitGraph.copySubject,
  ),
];

Future<String?> _promptBranchName(BuildContext context) {
  final l10n = context.l10n;
  return showTpTextPromptDialog(
    context,
    title: l10n.gitGraph.createBranchTitle,
    labelText: l10n.gitGraph.branchNameLabel,
    confirmLabel: l10n.gitGraph.create,
  ).then((value) => value?.trim());
}

/// 重命名对话框：预填旧分支名，返回新名字（取消返回 null）。
Future<String?> showRenameBranchDialog(BuildContext context, String oldName) {
  final l10n = context.l10n;
  return showTpTextPromptDialog(
    context,
    title: l10n.gitGraph.renameBranchTitle,
    initialText: oldName,
    labelText: l10n.gitGraph.branchNameLabel,
    confirmLabel: l10n.confirm,
  ).then((value) => value?.trim());
}

/// 标签名 + 可选说明；返回 `(name, message)`，取消返回 null。
Future<(String, String)?> _promptTagName(BuildContext context) {
  final l10n = context.l10n;
  return showDialog<(String, String)>(
    context: context,
    builder: (ctx) => _TagPromptDialog(
      title: l10n.gitGraph.createTagTitle,
      nameLabel: l10n.gitGraph.tagNameLabel,
      messageLabel: l10n.gitGraph.tagMessageLabel,
      confirmLabel: l10n.gitGraph.create,
    ),
  );
}

class _TagPromptDialog extends StatefulWidget {
  const _TagPromptDialog({
    required this.title,
    required this.nameLabel,
    required this.messageLabel,
    required this.confirmLabel,
  });

  final String title;
  final String nameLabel;
  final String messageLabel;
  final String confirmLabel;

  @override
  State<_TagPromptDialog> createState() => _TagPromptDialogState();
}

class _TagPromptDialogState extends State<_TagPromptDialog> {
  late final TextEditingController _name = TextEditingController();
  late final TextEditingController _message = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _message.dispose();
    super.dispose();
  }

  void _submit() =>
      Navigator.of(context).pop((_name.text.trim(), _message.text.trim()));

  @override
  Widget build(BuildContext context) {
    return TpDialog(
      maxWidth: 480,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TpDialogHeader(
            title: widget.title,
            onClose: () => Navigator.of(context).pop(),
          ),
          SizedBox(height: context.tpSpacing.lg),
          TpInput(
            controller: _name,
            autofocus: true,
            decoration: InputDecoration(labelText: widget.nameLabel),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 12),
          TpInput(
            controller: _message,
            decoration: InputDecoration(labelText: widget.messageLabel),
            onSubmitted: (_) => _submit(),
          ),
          TpDialogActions(
            children: [
              TpButton(
                variant: TpButtonVariant.ghost,
                onPressed: () => Navigator.of(context).pop(),
                child: Text(
                  MaterialLocalizations.of(context).cancelButtonLabel,
                ),
              ),
              TpButton(onPressed: _submit, child: Text(widget.confirmLabel)),
            ],
          ),
        ],
      ),
    );
  }
}

/// 危险操作确认。[typeToConfirm] 非空时，输入与之严格相等才启用红色确认按钮。
Future<bool> confirmDangerAction(
  BuildContext context, {
  required String title,
  required String body,
  String? typeToConfirm,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => _DangerConfirmDialog(
      title: title,
      body: body,
      typeToConfirm: typeToConfirm,
    ),
  );
  return confirmed ?? false;
}

class _DangerConfirmDialog extends StatefulWidget {
  const _DangerConfirmDialog({
    required this.title,
    required this.body,
    this.typeToConfirm,
  });

  final String title;
  final String body;

  /// 需要逐字输入的确认串（如当前分支名）；null/空表示无需输入。
  final String? typeToConfirm;

  @override
  State<_DangerConfirmDialog> createState() => _DangerConfirmDialogState();
}

class _DangerConfirmDialogState extends State<_DangerConfirmDialog> {
  late final TextEditingController _controller = TextEditingController();

  bool get _requiresTyping {
    final expected = widget.typeToConfirm;
    return expected != null && expected.isNotEmpty;
  }

  bool get _canConfirm =>
      !_requiresTyping || _controller.text == widget.typeToConfirm;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return TpDialog(
      maxWidth: 480,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TpDialogHeader(
            title: widget.title,
            onClose: () => Navigator.of(context).pop(),
          ),
          SizedBox(height: context.tpSpacing.lg),
          Text(widget.body),
          if (_requiresTyping) ...[
            SizedBox(height: context.tpSpacing.lg),
            TpInput(
              controller: _controller,
              autofocus: true,
              decoration: InputDecoration(hintText: widget.typeToConfirm),
            ),
          ],
          TpDialogActions(
            children: [
              TpButton(
                variant: TpButtonVariant.ghost,
                onPressed: () => Navigator.of(context).pop(),
                child: Text(l10n.cancel),
              ),
              TpButton(
                variant: TpButtonVariant.destructive,
                onPressed: _canConfirm
                    ? () => Navigator.of(context).pop(true)
                    : null,
                child: Text(l10n.confirm),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

Future<void> _copyAndNotify(
  BuildContext context, {
  required String text,
  required String message,
}) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (!context.mounted) return;
  ScaffoldMessenger.maybeOf(
    context,
  )?.showSnackBar(SnackBar(content: Text(message)));
}
