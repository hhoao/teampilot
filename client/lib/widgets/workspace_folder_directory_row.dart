import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../l10n/l10n_extensions.dart';
import '../models/runtime_target.dart';
import '../models/workspace_folder.dart';
import '../theme/app_text_styles.dart';
import '../theme/app_icon_sizes.dart';
import 'app_icon_button.dart';

/// Basename segment for display in folder lists.
String workspacePathBasename(String path) {
  final trimmed = path.trim();
  if (trimmed.isEmpty) return trimmed;
  if (trimmed.startsWith('~')) {
    final parts = trimmed.split('/').where((part) => part.isNotEmpty).toList();
    return parts.isEmpty ? trimmed : parts.last;
  }
  final ctx = trimmed.startsWith('/') && !trimmed.startsWith('//')
      ? p.Context(style: p.Style.posix)
      : p.context;
  final base = ctx.basename(trimmed);
  return base.isEmpty ? trimmed : base;
}

/// Parent path segment for display in folder lists.
String workspacePathParent(String path) {
  final trimmed = path.trim();
  if (trimmed.isEmpty) return '';
  if (trimmed.startsWith('~')) {
    final parts = trimmed.split('/').where((part) => part.isNotEmpty).toList();
    if (parts.length <= 1) {
      return trimmed == '~' || trimmed.startsWith('~/') ? '~' : trimmed;
    }
    return '~/${parts.sublist(0, parts.length - 1).join('/')}';
  }
  final ctx = trimmed.startsWith('/') && !trimmed.startsWith('//')
      ? p.Context(style: p.Style.posix)
      : p.context;
  final parent = ctx.dirname(trimmed);
  if (parent == trimmed || parent == '.' || parent.isEmpty) return '';
  return parent;
}

String workspaceFolderTargetLabel(
  List<RuntimeTarget> targets,
  String targetId,
) {
  for (final t in targets) {
    if (t.id == targetId) return t.label;
  }
  if (targetId == WorkspaceFolder.localTargetId) {
    return RuntimeTarget.local().label;
  }
  return targetId;
}

IconData workspaceFolderTargetIcon(String targetId) {
  return switch (runtimeKindOfId(targetId)) {
    RuntimeKind.ssh => Icons.dns_outlined,
    RuntimeKind.wsl => Icons.terminal_outlined,
    RuntimeKind.local => Icons.computer_outlined,
  };
}

/// Compact folder row inside a machine group or create-workspace picker.
class WorkspaceFolderDirectoryRow extends StatelessWidget {
  const WorkspaceFolderDirectoryRow({
    required this.folder,
    required this.isPrimary,
    required this.targets,
    this.onPickPath,
    this.onPickTarget,
    this.onRemove,
    this.showTarget = true,
    this.contentIndent = 58,
    super.key,
  });

  final WorkspaceFolder folder;
  final bool isPrimary;
  final List<RuntimeTarget> targets;
  final VoidCallback? onPickPath;
  final VoidCallback? onPickTarget;
  final VoidCallback? onRemove;
  final bool showTarget;
  final double contentIndent;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final styles = AppTextStyles.of(context);
    final path = folder.path.trim();
    final hasPath = path.isNotEmpty;
    final name = hasPath
        ? workspacePathBasename(path)
        : l10n.workspacePrimaryPathNotSelected;
    final parent = hasPath ? workspacePathParent(path) : '';
    final targetLabel = workspaceFolderTargetLabel(targets, folder.targetId);

    return Padding(
      padding: EdgeInsets.only(left: contentIndent, top: 6, bottom: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(
            isPrimary
                ? Icons.star_rounded
                : Icons.subdirectory_arrow_right_rounded,
            size: context.appIconSizes.sm,
            color: isPrimary ? cs.primary : cs.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: _pathLabel(
                name,
                parent,
                styles,
                cs,
                muted: !hasPath,
              ),
            ),
          ),
          if (showTarget) ...[
            const SizedBox(width: 8),
            _TargetChip(
              targetId: folder.targetId,
              targetLabel: targetLabel,
              onChange: onPickTarget,
            ),
          ],
          if (onPickPath != null)
            AppIconButton(
              icon: Icons.drive_file_rename_outline_rounded,
              onTap: onPickPath,
              size: AppIconButton.kCompactSize,
              compact: true,
              color: cs.onSurfaceVariant,
            ),
          if (onRemove != null)
            AppIconButton(
              icon: Icons.close_rounded,
              onTap: onRemove,
              size: AppIconButton.kCompactSize,
              compact: true,
              color: cs.onSurfaceVariant,
            ),
        ],
      ),
    );
  }

  static Widget _pathLabel(
    String name,
    String parent,
    AppTextStyles styles,
    ColorScheme cs, {
    required bool muted,
  }) {
    final titleColor = muted ? cs.onSurfaceVariant : cs.onSurface;
    final title = styles.body.copyWith(color: titleColor);
    final detail = styles.caption.copyWith(color: cs.onSurfaceVariant);
    if (parent.isEmpty) {
      return Text(
        name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: title.copyWith(
          fontWeight: muted ? FontWeight.w500 : FontWeight.w600,
          fontStyle: muted ? FontStyle.italic : FontStyle.normal,
        ),
      );
    }
    return Text.rich(
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      TextSpan(
        children: [
          TextSpan(
            text: name,
            style: title.copyWith(fontWeight: FontWeight.w600),
          ),
          TextSpan(text: ' · ', style: detail),
          TextSpan(text: parent, style: detail),
        ],
      ),
    );
  }
}

class _TargetChip extends StatelessWidget {
  const _TargetChip({
    required this.targetId,
    required this.targetLabel,
    this.onChange,
  });

  final String targetId;
  final String targetLabel;
  final VoidCallback? onChange;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final styles = AppTextStyles.of(context);
    final label = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          workspaceFolderTargetIcon(targetId),
          size: context.appIconSizes.sm,
          color: cs.onSurfaceVariant,
        ),
        const SizedBox(width: 4),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 120),
          child: Text(
            targetLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: styles.caption.copyWith(color: cs.onSurfaceVariant),
          ),
        ),
      ],
    );
    if (onChange == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: label,
      );
    }
    return TextButton(
      onPressed: onChange,
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: label,
    );
  }
}
