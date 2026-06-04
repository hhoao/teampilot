import 'package:flutter/material.dart';
import 'package:teampilot/theme/app_icon_sizes.dart';
import 'package:path/path.dart' as p;

import '../../l10n/l10n_extensions.dart';
import '../../theme/app_text_styles.dart';
import '../../theme/workspace_surface_layers.dart';
import '../../widgets/app_icon_button.dart';
import '../../widgets/dropdown/app_dropdown_decoration.dart';
import '../../widgets/dropdown/app_dropdown_field.dart';
import '../../widgets/menu/sidebar_action_menu.dart';
import 'log_viewer_filter.dart';

class LogViewerToolbar extends StatelessWidget {
  const LogViewerToolbar({
    required this.logFiles,
    required this.selectedFile,
    required this.searchController,
    required this.selectedLevel,
    required this.compactView,
    required this.wrapLines,
    required this.reverseOrder,
    required this.lineCount,
    required this.onFileSelected,
    required this.onSearchChanged,
    required this.onLevelChanged,
    required this.onCompactViewChanged,
    required this.onWrapLinesChanged,
    required this.onRefresh,
    required this.onCopyPath,
    required this.onClearOld,
    required this.onReverseOrderChanged,
    super.key,
  });

  final List<String> logFiles;
  final String? selectedFile;
  final TextEditingController searchController;
  final String selectedLevel;
  final bool compactView;
  final bool wrapLines;
  final bool reverseOrder;
  final int lineCount;
  final ValueChanged<String> onFileSelected;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String> onLevelChanged;
  final ValueChanged<bool> onCompactViewChanged;
  final ValueChanged<bool> onWrapLinesChanged;
  final Future<void> Function() onRefresh;
  final Future<void> Function() onCopyPath;
  final Future<void> Function() onClearOld;
  final ValueChanged<bool> onReverseOrderChanged;

  static const _controlHeight = 36.0;
  static const _verticalPadding = 10.0;
  static const _dropdownPadding = EdgeInsets.symmetric(
    vertical: 4,
    horizontal: 10,
  );

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final fileValue = selectedFile ?? (logFiles.isNotEmpty ? logFiles.first : null);

    return Container(
      padding: const EdgeInsets.fromLTRB(
        12,
        _verticalPadding,
        8,
        _verticalPadding,
      ),
      decoration: BoxDecoration(
        color: cs.workspaceInset,
        border: Border(
          bottom: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.4)),
        ),
      ),
      child: SizedBox(
        height: _controlHeight,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (fileValue != null) ...[
              _dropdown<String>(
                context: context,
                width: 168,
                items: logFiles,
                value: fileValue,
                itemLabel: p.basename,
                onChanged: (v) {
                  if (v != null) onFileSelected(v);
                },
              ),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: TextField(
                controller: searchController,
                style: AppTextStyles.of(context).body,
                decoration: _fieldDecoration(
                  context,
                  hintText: l10n.logViewerSearchHint,
                  prefixIcon: Icon(
                    Icons.search,
                    size: AppIconSizes.md,
                    color: cs.onSurfaceVariant,
                  ),
                ),
                onChanged: (value) => onSearchChanged(value),
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              fit: FlexFit.loose,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _dropdown<String>(
                      context: context,
                      width: 108,
                      items: kLogViewerLevels,
                      value: selectedLevel,
                      itemLabel: (l) => l,
                      onChanged: (v) {
                        if (v != null) onLevelChanged(v);
                      },
                    ),
                    const SizedBox(width: 4),
                    _iconToggle(
                      context: context,
                      tooltip: l10n.logViewerCompactView,
                      onIcon: Icons.filter_alt,
                      offIcon: Icons.filter_alt_outlined,
                      value: compactView,
                      onPressed: () => onCompactViewChanged(!compactView),
                    ),
                    _iconToggle(
                      context: context,
                      tooltip: l10n.logViewerWrapLines,
                      onIcon: Icons.wrap_text,
                      offIcon: Icons.wrap_text_outlined,
                      value: wrapLines,
                      onPressed: () => onWrapLinesChanged(!wrapLines),
                    ),
                    SidebarActionMenuButton(
                      tooltip: l10n.logViewerActionsMenu,
                      icon: Icon(Icons.more_horiz, color: cs.onSurfaceVariant),
                      specs: [
                        SidebarActionMenuSpec.item(
                          value: 'refresh',
                          icon: Icons.refresh,
                          label: l10n.logViewerRefresh,
                        ),
                        SidebarActionMenuSpec.item(
                          value: 'copy',
                          icon: Icons.copy_outlined,
                          label: l10n.logViewerCopyPath,
                        ),
                        SidebarActionMenuSpec.item(
                          value: 'clear',
                          icon: Icons.cleaning_services_outlined,
                          label: l10n.logViewerClearOld,
                        ),
                        SidebarActionMenuSpec.item(
                          value: 'reverse',
                          icon: Icons.swap_vert,
                          label: l10n.logViewerReverseOrder,
                          selected: reverseOrder,
                        ),
                      ],
                      onSelected: (action) async {
                        switch (action) {
                          case 'refresh':
                            await onRefresh();
                          case 'copy':
                            await onCopyPath();
                          case 'clear':
                            await onClearOld();
                          case 'reverse':
                            onReverseOrderChanged(!reverseOrder);
                        }
                      },
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: cs.primaryContainer.withValues(alpha: 0.65),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        l10n.logViewerLineCount(lineCount),
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: cs.onPrimaryContainer,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _fieldDecoration(
    BuildContext context, {
    String? hintText,
    Widget? prefixIcon,
  }) {
    final cs = Theme.of(context).colorScheme;
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.55)),
    );
    return InputDecoration(
      hintText: hintText,
      hintStyle: AppTextStyles.of(
        context,
      ).body.copyWith(color: cs.onSurfaceVariant),
      prefixIcon: prefixIcon,
      prefixIconConstraints: const BoxConstraints(minWidth: 34, minHeight: 34),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      filled: true,
      fillColor: cs.workspaceInset,
      border: border,
      enabledBorder: border,
      focusedBorder: border.copyWith(
        borderSide: BorderSide(color: cs.primary.withValues(alpha: 0.65)),
      ),
    );
  }

  Widget _iconToggle({
    required BuildContext context,
    required String tooltip,
    required IconData onIcon,
    required IconData offIcon,
    required bool value,
    required VoidCallback onPressed,
  }) {
    final cs = Theme.of(context).colorScheme;
    return AppIconButton(
      icon: value ? onIcon : offIcon,
      iconSize: AppIconSizes.md,
      size: 36,
      tooltip: tooltip,
      color: value ? cs.onPrimaryContainer : cs.onSurfaceVariant,
      backgroundColor: value
          ? cs.primaryContainer.withValues(alpha: 0.7)
          : cs.workspaceInset,
      onTap: onPressed,
    );
  }

  Widget _dropdown<T extends Object>({
    required BuildContext context,
    required double width,
    required List<T> items,
    required T value,
    required String Function(T) itemLabel,
    required ValueChanged<T?> onChanged,
  }) {
    return SizedBox(
      width: width,
      height: _controlHeight,
      child: AppDropdownField<T>(
        key: ValueKey<T>(value),
        items: items,
        initialItem: value,
        decoration: AppDropdownDecorations.themed(context),
        closedHeaderPadding: _dropdownPadding,
        expandedHeaderPadding: _dropdownPadding,
        itemLabel: itemLabel,
        onChanged: onChanged,
      ),
    );
  }
}
