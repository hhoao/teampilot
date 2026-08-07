import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../pages/home_workspace/workspace/workspace_chat_landing_palette.dart';
import '../../services/compose/compose_at_file_refs.dart';
import '../../services/editor/file_editor_theme.dart';
import 'compose_menu_chip.dart';

/// Horizontal mirror of `@` file references above the compose input.
class ComposeAtFileChipRow extends StatelessWidget {
  const ComposeAtFileChipRow({
    required this.refs,
    required this.onOpen,
    super.key,
  });

  final List<ComposeAtFileRef> refs;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    if (refs.isEmpty) return const SizedBox.shrink();

    final palette = WorkspaceChatLandingPalette(
      Theme.of(context).colorScheme,
    );
    final spacing = context.tpSpacing;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 0; i < refs.length; i++) ...[
            if (i > 0) SizedBox(width: spacing.xs),
            _ComposeAtFileChip(
              ref: refs[i],
              palette: palette,
              onTap: () => onOpen(refs[i].absolutePath),
            ),
          ],
        ],
      ),
    );
  }
}

class _ComposeAtFileChip extends StatelessWidget {
  const _ComposeAtFileChip({
    required this.ref,
    required this.palette,
    required this.onTap,
  });

  final ComposeAtFileRef ref;
  final WorkspaceChatLandingPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final spacing = context.tpSpacing;
    final icons = context.tpIconSizes;
    final labelStyle = TpTextStyles.of(
      context,
    ).smColored(palette.muted);

    return TpHover(
      backgroundColor: palette.chipFill,
      shape: TpPressableShape.stadium,
      border: Border.all(color: palette.border),
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minHeight: ComposeToolbarChip.minHeight,
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: spacing.md,
            vertical: spacing.sm,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _ComposeAtFileChipLeading(
                path: ref.absolutePath,
                palette: palette,
                iconSize: icons.sm,
              ),
              SizedBox(width: spacing.xs),
              Text(ref.displayName, style: labelStyle),
            ],
          ),
        ),
      ),
    );
  }
}

class _ComposeAtFileChipLeading extends StatelessWidget {
  const _ComposeAtFileChipLeading({
    required this.path,
    required this.palette,
    required this.iconSize,
  });

  final String path;
  final WorkspaceChatLandingPalette palette;
  final double iconSize;

  static const double _thumbnailSize = 20;

  @override
  Widget build(BuildContext context) {
    if (isImagePreviewPath(path)) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Image.file(
          File(path),
          width: _thumbnailSize,
          height: _thumbnailSize,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => _fileIcon,
        ),
      );
    }
    return _fileIcon;
  }

  Widget get _fileIcon => Icon(
    Icons.insert_drive_file_outlined,
    size: iconSize,
    color: palette.muted,
  );
}
