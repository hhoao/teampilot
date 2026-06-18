import 'package:flutter/material.dart';

import '../l10n/l10n_extensions.dart';
import '../theme/app_dialog_theme.dart';
import '../theme/app_icon_sizes.dart';
import '../theme/app_text_styles.dart';
import '../theme/workspace_surface_layers.dart';

/// Shared shell for the app's centered modal dialogs.
///
/// Wraps a bare [Dialog] with the one thing `DialogThemeData` cannot carry —
/// content padding — plus the width/height constraints every modal repeats.
/// Shape, inset padding, surface tint, and barrier color come from the global
/// `dialogTheme`; only the workspace background is overridden here so cards read
/// as elevated against the subtle dialog surface used elsewhere.
///
/// Pair with [AppDialogHeader] for the title row + close affordance.
class AppDialog extends StatelessWidget {
  const AppDialog({
    super.key,
    required this.child,
    this.maxWidth = 640,
    this.maxHeight,
    this.contentPadding = kAppDialogContentPadding,
    this.scrollable = false,
    this.backgroundColor,
  });

  /// The dialog body. Typically a [Column] starting with an [AppDialogHeader].
  final Widget child;

  /// Maximum content width before the dialog stops growing horizontally.
  final double maxWidth;

  /// Optional maximum height; when set, pair with [scrollable] so overflowing
  /// content can scroll instead of clipping.
  final double? maxHeight;

  /// Inner padding around [child]. Defaults to [kAppDialogContentPadding].
  final EdgeInsets contentPadding;

  /// When true, [child] is wrapped in a [SingleChildScrollView] so tall content
  /// scrolls within [maxHeight] instead of overflowing.
  final bool scrollable;

  /// Overrides the dialog surface. Defaults to the workspace card color.
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final body = scrollable
        ? SingleChildScrollView(padding: contentPadding, child: child)
        : Padding(padding: contentPadding, child: child);

    return Dialog(
      backgroundColor: backgroundColor ?? cs.workspaceCard,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: maxWidth,
          maxHeight: maxHeight ?? double.infinity,
        ),
        child: body,
      ),
    );
  }
}

/// Section divider that spans the full [AppDialog] width inside content padding.
///
/// [horizontalInset] should match [AppDialog.contentPadding]'s horizontal insets
/// when callers override the default [kAppDialogContentPadding].
class AppDialogDivider extends StatelessWidget {
  const AppDialogDivider({
    super.key,
    this.horizontalInset = kAppDialogContentHorizontalInset,
  });

  final double horizontalInset;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final fullWidth = constraints.maxWidth + horizontalInset * 2;
        return SizedBox(
          height: 1,
          child: OverflowBox(
            maxWidth: fullWidth,
            minWidth: fullWidth,
            alignment: Alignment.center,
            child: Divider(
              height: 1,
              thickness: 1,
              color: cs.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
        );
      },
    );
  }
}

/// End-aligned action row for [AppDialog] footers (replaces [AlertDialog.actions]).
class AppDialogActions extends StatelessWidget {
  const AppDialogActions({
    super.key,
    required this.children,
    this.showDividerAbove = true,
    this.horizontalInset = kAppDialogContentHorizontalInset,
  });

  final List<Widget> children;

  /// When true (default), draws a full-width [AppDialogDivider] above the row.
  final bool showDividerAbove;

  /// Horizontal bleed for [AppDialogDivider]; match [AppDialog.contentPadding].
  final double horizontalInset;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showDividerAbove) ...[
          const SizedBox(height: 16),
          AppDialogDivider(horizontalInset: horizontalInset),
        ],
        Padding(
          padding: EdgeInsets.only(top: showDividerAbove ? 16 : 24),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                children[i],
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Dialog title with a top-right close button.
///
/// [titleAlignment] controls horizontal title placement. Defaults to
/// [Alignment.topLeft]; use [Alignment.center] when the title should sit in the
/// middle of the header (close button stays top-right).
class AppDialogHeader extends StatelessWidget {
  const AppDialogHeader({
    super.key,
    required this.title,
    this.onClose,
    this.titleAlignment = Alignment.topLeft,
    this.showDividerBelow = true,
    this.horizontalInset = kAppDialogContentHorizontalInset,
  });

  final String title;

  /// Defaults to popping the enclosing [Navigator].
  final VoidCallback? onClose;

  /// Title alignment within the header row. [Alignment.center] centers the label;
  /// [Alignment.topLeft] left-aligns it (default).
  final Alignment titleAlignment;

  /// When true (default), draws a full-width [AppDialogDivider] below the title.
  final bool showDividerBelow;

  /// Horizontal bleed for [AppDialogDivider]; match [AppDialog.contentPadding].
  final double horizontalInset;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final styles = AppTextStyles.of(context);
    final centered = titleAlignment == Alignment.center;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            Padding(
              padding: const EdgeInsets.only(right: 40),
              child: SizedBox(
                width: double.infinity,
                child: Text(
                  title,
                  textAlign: centered ? TextAlign.center : TextAlign.start,
                  style: styles.dialogTitle.copyWith(
                    color: cs.onSurface,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            Positioned(
              right: 0,
              top: 0,
              child: IconButton(
                tooltip: context.l10n.cancel,
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  Icons.close_rounded,
                  size: context.appIconSizes.md,
                  color: cs.onSurfaceVariant,
                ),
                onPressed: onClose ?? () => Navigator.of(context).pop(),
              ),
            ),
          ],
        ),
        if (showDividerBelow) ...[
          const SizedBox(height: 16),
          AppDialogDivider(horizontalInset: horizontalInset),
        ],
      ],
    );
  }
}

/// Single-line text prompt dialog with correct [TextEditingController] lifecycle.
///
/// Returns the entered text on confirm, or `null` on cancel/close.
Future<String?> showAppTextPromptDialog(
  BuildContext context, {
  required String title,
  String initialText = '',
  String? hintText,
  String? labelText,
  required String confirmLabel,
  double maxWidth = 480,
}) {
  return showDialog<String>(
    context: context,
    builder: (ctx) => AppTextPromptDialog(
      title: title,
      initialText: initialText,
      hintText: hintText,
      labelText: labelText,
      confirmLabel: confirmLabel,
      maxWidth: maxWidth,
    ),
  );
}

class AppTextPromptDialog extends StatefulWidget {
  const AppTextPromptDialog({
    super.key,
    required this.title,
    this.initialText = '',
    this.hintText,
    this.labelText,
    required this.confirmLabel,
    this.maxWidth = 480,
  });

  final String title;
  final String initialText;
  final String? hintText;
  final String? labelText;
  final String confirmLabel;
  final double maxWidth;

  @override
  State<AppTextPromptDialog> createState() => _AppTextPromptDialogState();
}

class _AppTextPromptDialogState extends State<AppTextPromptDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() => Navigator.of(context).pop(_controller.text);

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AppDialog(
      maxWidth: widget.maxWidth,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppDialogHeader(
            title: widget.title,
            onClose: () => Navigator.of(context).pop(),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            autofocus: true,
            decoration: InputDecoration(
              hintText: widget.hintText,
              labelText: widget.labelText,
            ),
            onSubmitted: (_) => _submit(),
          ),
          AppDialogActions(
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(l10n.cancel),
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
