import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../l10n/l10n_extensions.dart';
import '../../../services/session/workspace_session_content_index.dart';
import '../../../utils/ui/coarse_relative_time.dart';

/// Route-scoped widgets for the workspace search dialog (`workspace_search_dialog.dart`),
/// styled after the search-panel mockup (`test.html`): a rounded search field, filter
/// chips, and grouped result rows with `mark`-style query highlights.

/// Rounded search field pinned to the top of the dialog. No label, no fill —
/// just an outlined pill with a search prefix and a clear suffix when text is present.
class WorkspaceSearchField extends StatelessWidget {
  const WorkspaceSearchField({
    required this.controller,
    required this.hint,
    required this.onChanged,
    required this.onClear,
    super.key,
  });

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final styles = TpTextStyles.of(context);
    return SizedBox(
      height: 44,
      child: TextField(
        controller: controller,
        autofocus: true,
        style: styles.mdColored(cs.onSurface),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: styles.mdColored(cs.onSurfaceVariant),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14),
          prefixIcon: Icon(
            Icons.search_rounded,
            size: 16,
            color: cs.onSurfaceVariant,
          ),
          floatingLabelBehavior: FloatingLabelBehavior.never,
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: cs.outlineVariant),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: cs.primary),
          ),
          suffixIcon: controller.text.isNotEmpty
              ? TpIconButton(
                  icon: Icons.clear,
                  compact: true,
                  size: TpIconButton.kCompactSize,
                  onTap: onClear,
                )
              : null,
        ),
        onChanged: onChanged,
      ),
    );
  }
}

/// Single-select filter chip (全部 / 任务 / 文件): icon + label, light-gray fill when
/// active, soft hover otherwise.
class WorkspaceSearchFilterChip extends StatelessWidget {
  const WorkspaceSearchFilterChip({
    required this.label,
    required this.icon,
    required this.active,
    required this.onTap,
    super.key,
  });

  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final styles = TpTextStyles.of(context);
    final color = active ? cs.onSurface : cs.onSurfaceVariant;
    return TpHover(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      hoverColor: cs.onSurface.withValues(alpha: active ? 0.08 : 0.05),
      backgroundColor: active
          ? cs.onSurface.withValues(alpha: 0.06)
          : Colors.transparent,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: styles.mdColored(color).copyWith(
              fontWeight: active ? FontWeight.w500 : FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }
}

/// Gray section header (任务 / 文件 / 最近会话).
class WorkspaceSearchSectionHeader extends StatelessWidget {
  const WorkspaceSearchSectionHeader({required this.label, super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 10, 4, 6),
      child: Text(
        label,
        style: TpTextStyles.of(context).mdSemiboldColored(cs.onSurfaceVariant),
      ),
    );
  }
}

/// Muted one-line status / hint (正在索引… / 正在搜索文件…).
class WorkspaceSearchStatusRow extends StatelessWidget {
  const WorkspaceSearchStatusRow({required this.label, super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      child: Text(
        label,
        style: TpTextStyles.of(context).mdColored(cs.onSurfaceVariant),
      ),
    );
  }
}

/// Text with the first case-insensitive [query] occurrence drawn like an HTML
/// `<mark>`: light highlight background + semibold. Falls back to plain text
/// when there is no contiguous occurrence.
class WorkspaceSearchMarkedText extends StatelessWidget {
  const WorkspaceSearchMarkedText({
    required this.text,
    required this.query,
    required this.style,
    this.maxLines = 2,
    this.overflow = TextOverflow.ellipsis,
    super.key,
  });

  final String text;
  final String query;
  final TextStyle style;
  final int maxLines;
  final TextOverflow overflow;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final q = query.trim();
    final idx = q.isEmpty
        ? null
        : WorkspaceSessionContentIndex.caseInsensitiveIndexOf(text, q);
    if (idx == null) {
      return Text(text, maxLines: maxLines, overflow: overflow, style: style);
    }
    final end = idx + q.length;
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: text.substring(0, idx)),
          TextSpan(
            text: text.substring(idx, end),
            style: style.copyWith(
              backgroundColor: cs.primaryContainer,
              color: cs.onPrimaryContainer,
              fontWeight: FontWeight.w600,
            ),
          ),
          TextSpan(text: text.substring(end)),
        ],
      ),
      maxLines: maxLines,
      overflow: overflow,
    );
  }
}

/// A task/conversation result row: chat icon, title, optional monospace snippet
/// (query marked), and a right-aligned source / relative-time meta column.
/// Tapping opens the session.
class WorkspaceSearchConversationRow extends StatelessWidget {
  const WorkspaceSearchConversationRow({
    required this.title,
    required this.query,
    required this.activityTimestampMs,
    required this.onTap,
    this.snippet,
    this.source,
    super.key,
  });

  final String title;
  final String query;
  final String? snippet;
  final String? source;
  final int activityTimestampMs;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final styles = TpTextStyles.of(context);
    final timeLabel = formatCoarseRelativeTime(
      context.l10n,
      DateTime.fromMillisecondsSinceEpoch(activityTimestampMs),
    );

    return TpHover(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      hoverColor: cs.onSurface.withValues(alpha: 0.05),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 28,
            height: 28,
            child: Icon(
              Icons.chat_bubble_outline_rounded,
              size: 18,
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: styles.mdColored(cs.onSurface),
                ),
                if (snippet != null && snippet!.trim().isNotEmpty) ...[
                  const SizedBox(height: 3),
                  WorkspaceSearchMarkedText(
                    text: snippet!,
                    query: query,
                    style: styles.monoColored(cs.onSurfaceVariant),
                    maxLines: 1,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 140),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (source != null && source!.trim().isNotEmpty)
                  Text(
                    source!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: styles.xsColored(cs.onSurfaceVariant),
                  ),
                Text(
                  timeLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: styles.xsColored(cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A file result row: amber star icon, monospace file name (query marked), and a
/// right-aligned relative path. Tapping opens the file.
class WorkspaceSearchFileRow extends StatelessWidget {
  const WorkspaceSearchFileRow({
    required this.name,
    required this.query,
    required this.relativePath,
    required this.onTap,
    super.key,
  });

  final String name;
  final String query;
  final String relativePath;
  final VoidCallback onTap;

  /// Matches the mockup's `#f5a623` star accent.
  static const _starColor = Color(0xFFF5A623);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final styles = TpTextStyles.of(context);

    return TpHover(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      hoverColor: cs.onSurface.withValues(alpha: 0.05),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      child: Row(
        children: [
          SizedBox(
            width: 28,
            height: 28,
            child: Icon(Icons.star_rounded, size: 16, color: _starColor),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: WorkspaceSearchMarkedText(
              text: name,
              query: query,
              style: styles.monoColored(cs.onSurface),
              maxLines: 1,
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              relativePath,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
              style: styles.xsColored(cs.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

/// "查看更多结果" link that expands a truncated section to show all matches.
class WorkspaceSearchShowMore extends StatelessWidget {
  const WorkspaceSearchShowMore({
    required this.label,
    required this.onTap,
    super.key,
  });

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return TpHover(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      hoverColor: cs.onSurface.withValues(alpha: 0.05),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TpTextStyles.of(context).mdColored(cs.onSurfaceVariant),
          ),
          const SizedBox(width: 4),
          Icon(
            Icons.keyboard_arrow_down_rounded,
            size: 16,
            color: cs.onSurfaceVariant,
          ),
        ],
      ),
    );
  }
}
