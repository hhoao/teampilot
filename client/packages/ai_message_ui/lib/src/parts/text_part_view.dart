import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;

import '../strings.dart';
import '../theme.dart';

/// LRU-ish cache of [MarkdownBody] subtrees keyed by prepared markdown + style.
class MarkdownBodyCache {
  MarkdownBodyCache({this.maxEntries = 64});

  final int maxEntries;
  final _map = <String, Widget>{};

  Widget getOrCreate(String key, Widget Function() build) {
    final hit = _map[key];
    if (hit != null) return hit;
    final w = build();
    if (_map.length >= maxEntries) _map.remove(_map.keys.first);
    _map[key] = w;
    return w;
  }

  @visibleForTesting
  int get debugLength => _map.length;
}

final MarkdownBodyCache _markdownBodyCache = MarkdownBodyCache();

/// Stable cache key for [MarkdownBody] — never allocates a style sheet.
@visibleForTesting
String markdownBodyCacheKey({
  required String preparedMarkdown,
  required ThemeData theme,
  required AiMessageTheme aiTheme,
  MarkdownTapLinkCallback? onTapLink,
}) {
  final String styleKey;
  final customSheet = aiTheme.markdownStyleSheet;
  if (customSheet != null) {
    styleKey = 'sheet:${identityHashCode(customSheet)}';
  } else {
    // Tokens that feed [defaultAiMarkdownSheet] without building the sheet.
    final mutedArgb = aiTheme.mutedSurface?.toARGB32() ?? 0;
    styleKey =
        'default:${theme.brightness.name}|$mutedArgb|${aiTheme.codeBlockRadius}';
  }
  final linkKey =
      onTapLink == null ? '0' : '${identityHashCode(onTapLink)}';
  return '$preparedMarkdown|$styleKey|$linkKey';
}

/// Streaming-safe markdown aligned with assistant-ui MarkdownText / aui-md.
class AiTextPartView extends StatelessWidget {
  const AiTextPartView({
    required this.text,
    this.onTapLink,
    super.key,
  });

  final String text;

  /// Optional; package does not launch URLs itself.
  final MarkdownTapLinkCallback? onTapLink;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final aiTheme = AiMessageTheme.of(context);
    final data = prepareStreamingMarkdown(text);
    final sheet =
        aiTheme.markdownStyleSheet ?? defaultAiMarkdownSheet(theme, aiTheme);
    final cacheKey = markdownBodyCacheKey(
      preparedMarkdown: data,
      theme: theme,
      aiTheme: aiTheme,
      onTapLink: onTapLink,
    );

    return _markdownBodyCache.getOrCreate(
      cacheKey,
      () => MarkdownBody(
        data: data,
        styleSheet: sheet,
        onTapLink: onTapLink,
        // Parent [SelectionArea]: text-only blocks merge into one Text.rich;
        // code blocks / tables stay as widgets and split the tree.
        selectable: false,
        builders: {
          'pre': _AuiCodeBlockBuilder(aiTheme: aiTheme),
        },
      ),
    );
  }
}

/// Exposed for tests / hosts that want the same fence repair rules.
String prepareStreamingMarkdown(String raw) {
  // Match line-start fences including indented ones (CommonMark-ish).
  final fenceCount =
      RegExp(r'^[ \t]{0,3}```', multiLine: true).allMatches(raw).length;
  if (fenceCount.isOdd) {
    return '$raw\n```';
  }
  return raw;
}

MarkdownStyleSheet defaultAiMarkdownSheet(
  ThemeData theme,
  AiMessageTheme aiTheme,
) {
  final scheme = theme.colorScheme;
  final base = MarkdownStyleSheet.fromTheme(theme);
  final body = theme.textTheme.bodyMedium?.copyWith(height: 1.625);
  final muted = aiTheme.resolveMutedSurface(scheme);
  final borderColor = scheme.outlineVariant.withValues(alpha: 0.55);
  return base.copyWith(
    p: body?.copyWith(height: 1.625),
    h1: theme.textTheme.titleLarge?.copyWith(
      fontWeight: FontWeight.w600,
      height: 1.25,
    ),
    h2: theme.textTheme.titleMedium?.copyWith(
      fontWeight: FontWeight.w600,
      height: 1.3,
    ),
    h3: theme.textTheme.titleSmall?.copyWith(
      fontWeight: FontWeight.w600,
      height: 1.35,
    ),
    // assistant-ui aui-md: inter-block spacing via element margins (`my-3`),
    // not empty spacer widgets. Here blockSpacing → top Padding on siblings.
    blockSpacing: 12,
    h1Padding: const EdgeInsets.only(top: 8),
    h2Padding: const EdgeInsets.only(top: 8),
    h3Padding: const EdgeInsets.only(top: 4),
    listIndent: 24,
    listBullet: body,
    a: body?.copyWith(
      color: scheme.primary,
      decoration: TextDecoration.underline,
      decorationColor: scheme.primary,
    ),
    // Same size/height as body — mismatched inline code metrics fragment
    // SelectionArea highlights (copy still works; it only looks gapped).
    code: body?.copyWith(
      fontFamily: 'monospace',
      backgroundColor: muted.withValues(alpha: 0.55),
    ),
    codeblockDecoration: BoxDecoration(
      color: muted,
      borderRadius: BorderRadius.circular(aiTheme.codeBlockRadius),
    ),
    codeblockPadding: EdgeInsets.zero,
    blockquoteDecoration: BoxDecoration(
      border: Border(
        left: BorderSide(
          color: scheme.outlineVariant,
          width: 3,
        ),
      ),
    ),
    blockquotePadding: const EdgeInsets.only(left: 12),
    tableHead: body?.copyWith(fontWeight: FontWeight.w600),
    tableBody: body,
    tableHeadAlign: TextAlign.start,
    tableBorder: TableBorder.all(color: borderColor, width: 1),
    tableColumnWidth: const IntrinsicColumnWidth(),
    tableCellsPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    tableHeadCellsDecoration: BoxDecoration(color: muted.withValues(alpha: 0.85)),
    tableCellsDecoration: const BoxDecoration(),
    tablePadding: const EdgeInsets.symmetric(vertical: 8),
  );
}

class _AuiCodeBlockBuilder extends MarkdownElementBuilder {
  _AuiCodeBlockBuilder({required this.aiTheme});

  final AiMessageTheme aiTheme;

  @override
  bool isBlockElement() => true;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    var language = '';
    var code = element.textContent;
    if (element.children != null) {
      for (final child in element.children!) {
        if (child is md.Element && child.tag == 'code') {
          final classes = child.attributes['class'] ?? '';
          final match = RegExp(r'language-(\S+)').firstMatch(classes);
          language = match?.group(1) ?? '';
          code = child.textContent;
        }
      }
    }

    return _CodeBlock(
      language: language,
      code: code,
      aiTheme: aiTheme,
    );
  }
}

class _CodeBlock extends StatefulWidget {
  const _CodeBlock({
    required this.language,
    required this.code,
    required this.aiTheme,
  });

  final String language;
  final String code;
  final AiMessageTheme aiTheme;

  @override
  State<_CodeBlock> createState() => _CodeBlockState();
}

class _CodeBlockState extends State<_CodeBlock> {
  bool _copied = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final strings = AiMessageStrings.of(context);
    final muted = widget.aiTheme.resolveMutedSurface(scheme);
    final radius = widget.aiTheme.codeBlockRadius;
    final lang = widget.language.isEmpty
        ? strings.code
        : widget.language.toLowerCase();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: muted,
              borderRadius: BorderRadius.vertical(top: Radius.circular(radius)),
              border: Border(
                top: BorderSide(
                  color: scheme.outlineVariant.withValues(alpha: 0.5),
                ),
                left: BorderSide(
                  color: scheme.outlineVariant.withValues(alpha: 0.5),
                ),
                right: BorderSide(
                  color: scheme.outlineVariant.withValues(alpha: 0.5),
                ),
              ),
            ),
            child: SelectionContainer.disabled(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        lang,
                        style:
                            Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: _copied ? strings.copied : strings.copy,
                      iconSize: 16,
                      onPressed: () async {
                        await Clipboard.setData(
                          ClipboardData(text: widget.code),
                        );
                        if (!mounted) return;
                        setState(() => _copied = true);
                        await Future<void>.delayed(
                          const Duration(milliseconds: 1600),
                        );
                        if (!mounted) return;
                        setState(() => _copied = false);
                      },
                      icon: Icon(
                        _copied ? Icons.check_rounded : Icons.copy_rounded,
                        size: 16,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              color: muted,
              borderRadius:
                  BorderRadius.vertical(bottom: Radius.circular(radius)),
              border: Border.all(
                color: scheme.outlineVariant.withValues(alpha: 0.5),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
              child: Text(
                widget.code,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontFamily: 'monospace',
                  height: 1.45,
                  color: scheme.onSurface,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
