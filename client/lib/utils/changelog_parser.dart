import 'package:flutter/material.dart';

/// A version section parsed from changelog markdown.
class ChangelogEntry {
  const ChangelogEntry({required this.version, required this.items});

  final String version;
  final List<String> items;
}

/// Parses and renders backend changelog markdown.
class ChangelogData {
  static List<ChangelogEntry> parseMarkdownContent(
    String content, {
    String defaultSectionTitle = 'Updates',
  }) {
    final trimmed = content.trim();
    if (trimmed.isEmpty) return const [];

    final entries = <ChangelogEntry>[];
    String? currentVersion;
    final currentItems = <String>[];

    void flush() {
      if (currentVersion == null && currentItems.isEmpty) return;
      entries.add(
        ChangelogEntry(
          version: currentVersion ?? defaultSectionTitle,
          items: List.unmodifiable(currentItems),
        ),
      );
      currentItems.clear();
    }

    for (final line in trimmed.split('\n')) {
      final text = line.trim();
      if (text.isEmpty) continue;

      if (text.startsWith('## ')) {
        flush();
        currentVersion = text.substring(3).trim();
        continue;
      }
      if (text.startsWith('# ')) {
        flush();
        currentVersion = text.substring(2).trim();
        continue;
      }

      final item = text.startsWith('- ') || text.startsWith('* ')
          ? text.substring(2).trim()
          : text;
      if (item.isNotEmpty) {
        if (currentVersion == null && entries.isEmpty && currentItems.isEmpty) {
          currentVersion = defaultSectionTitle;
        }
        currentItems.add(item);
      }
    }
    flush();

    if (entries.isEmpty) {
      return [
        ChangelogEntry(version: defaultSectionTitle, items: [trimmed]),
      ];
    }
    return entries;
  }

  static Widget buildChangelogItem(BuildContext context, ChangelogEntry entry) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          entry.version,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        for (final item in entry.items)
          Padding(
            padding: const EdgeInsets.only(left: 8, bottom: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('• ', style: theme.textTheme.bodySmall),
                Expanded(
                  child: Text(item, style: theme.textTheme.bodySmall),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
