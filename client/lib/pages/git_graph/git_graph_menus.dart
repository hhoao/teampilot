import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/git_graph_actions_controller.dart';
import '../../cubits/git_graph_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/git_graph.dart';

/// 行级右键 / 长按菜单：checkout 本地分支、在此建分支 / 标签、cherry-pick、
/// revert、reset（hard 需输入当前分支名确认）与复制哈希 / 说明。
/// 所有写操作经 [GitGraphActionsController]；成败反馈由状态栏错误区呈现。
Future<void> showCommitContextMenu(
  BuildContext context,
  Offset position,
  GitCommitRow row,
  GitGraphActionsController actions,
  GitGraphState state,
) async {
  String? localBranch;
  for (final ref in row.refs) {
    if (ref.kind == GitRefDecorationKind.localBranch) {
      localBranch = ref.name;
      break;
    }
  }
  final l10n = context.l10n;
  final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
  final local = overlay.globalToLocal(position);
  final choice = await showMenu<String>(
    context: context,
    position: RelativeRect.fromLTRB(
      local.dx,
      local.dy,
      local.dx + 1,
      local.dy + 1,
    ),
    items: _menuItems(l10n, localBranch),
  );
  if (choice == null || !context.mounted) return;
  switch (choice) {
    case 'checkout':
      if (localBranch != null) await actions.checkoutBranch(localBranch);
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
    case 'cherry-pick':
      await actions.cherryPick(row.hash);
    case 'revert':
      final confirmed = await confirmDangerAction(
        context,
        title: l10n.gitGraphRevert,
        body: l10n.gitGraphRevertConfirmBody(row.hash),
      );
      if (confirmed && context.mounted) await actions.revert(row.hash);
    case 'reset-hard':
      final branch = state.currentBranch;
      final confirmed = await confirmDangerAction(
        context,
        title: l10n.gitGraphResetHard,
        body: l10n.gitGraphResetHardConfirmBody(branch),
        typeToConfirm: branch,
      );
      if (confirmed && context.mounted) {
        await actions.resetTo(row.hash, mode: GitResetMode.hard);
      }
    case 'reset-soft':
      await actions.resetTo(row.hash, mode: GitResetMode.soft);
    case 'reset-mixed':
      await actions.resetTo(row.hash, mode: GitResetMode.mixed);
    case 'copy-hash':
      await _copyAndNotify(
        context,
        text: row.hash,
        message: l10n.gitGraphHashCopied,
      );
    case 'copy-subject':
      await _copyAndNotify(
        context,
        text: row.subject,
        message: l10n.gitGraphSubjectCopied,
      );
  }
}

List<PopupMenuEntry<String>> _menuItems(
  AppLocalizations l10n,
  String? localBranch,
) => [
  if (localBranch != null)
    PopupMenuItem<String>(
      value: 'checkout',
      child: Text(l10n.gitGraphCheckoutBranch(localBranch)),
    ),
  PopupMenuItem<String>(
    value: 'create-branch',
    child: Text(l10n.gitGraphCreateBranchHere),
  ),
  PopupMenuItem<String>(
    value: 'create-tag',
    child: Text(l10n.gitGraphCreateTagHere),
  ),
  PopupMenuItem<String>(
    value: 'cherry-pick',
    child: Text(l10n.gitGraphCherryPick),
  ),
  PopupMenuItem<String>(value: 'revert', child: Text(l10n.gitGraphRevert)),
  PopupMenuItem<String>(enabled: false, child: Text(l10n.gitGraphReset)),
  PopupMenuItem<String>(
    value: 'reset-soft',
    height: 34,
    child: Padding(
      padding: const EdgeInsets.only(left: 12),
      child: Text(l10n.gitGraphResetSoft),
    ),
  ),
  PopupMenuItem<String>(
    value: 'reset-mixed',
    height: 34,
    child: Padding(
      padding: const EdgeInsets.only(left: 12),
      child: Text(l10n.gitGraphResetMixed),
    ),
  ),
  PopupMenuItem<String>(
    value: 'reset-hard',
    height: 34,
    child: Padding(
      padding: const EdgeInsets.only(left: 12),
      child: Text(l10n.gitGraphResetHard),
    ),
  ),
  const PopupMenuDivider(),
  PopupMenuItem<String>(value: 'copy-hash', child: Text(l10n.gitGraphCopyHash)),
  PopupMenuItem<String>(
    value: 'copy-subject',
    child: Text(l10n.gitGraphCopySubject),
  ),
];

Future<String?> _promptBranchName(BuildContext context) {
  final l10n = context.l10n;
  return showTpTextPromptDialog(
    context,
    title: l10n.gitGraphCreateBranchTitle,
    labelText: l10n.gitGraphBranchNameLabel,
    confirmLabel: l10n.gitGraphCreate,
  ).then((value) => value?.trim());
}

/// 标签名 + 可选说明；返回 `(name, message)`，取消返回 null。
Future<(String, String)?> _promptTagName(BuildContext context) {
  final l10n = context.l10n;
  return showDialog<(String, String)>(
    context: context,
    builder: (ctx) => _TagPromptDialog(
      title: l10n.gitGraphCreateTagTitle,
      nameLabel: l10n.gitGraphTagNameLabel,
      messageLabel: l10n.gitGraphTagMessageLabel,
      confirmLabel: l10n.gitGraphCreate,
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
          TextField(
            controller: _name,
            autofocus: true,
            decoration: InputDecoration(labelText: widget.nameLabel),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _message,
            decoration: InputDecoration(labelText: widget.messageLabel),
            onSubmitted: (_) => _submit(),
          ),
          TpDialogActions(
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(
                  MaterialLocalizations.of(context).cancelButtonLabel,
                ),
              ),
              FilledButton(
                onPressed: _submit,
                child: Text(widget.confirmLabel),
              ),
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
    final cs = Theme.of(context).colorScheme;
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
            TextField(
              controller: _controller,
              autofocus: true,
              decoration: InputDecoration(hintText: widget.typeToConfirm),
            ),
          ],
          TpDialogActions(
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(l10n.cancel),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: cs.error,
                  foregroundColor: cs.onError,
                  disabledBackgroundColor: cs.error.withValues(alpha: 0.38),
                  disabledForegroundColor: cs.onError.withValues(alpha: 0.6),
                ),
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
