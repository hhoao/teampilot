import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:teampilot/theme/app_icon_sizes.dart';

import '../../l10n/l10n_extensions.dart';
import '../../theme/workspace_surface_layers.dart';
import '../../utils/logger_utils.dart';
import 'log_helpers.dart';

class LogViewerCenteredMessage extends StatelessWidget {
  const LogViewerCenteredMessage({
    required this.icon,
    required this.title,
    required this.subtitle,
    super.key,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: context.appIconSizes.md,
              color: cs.primary.withValues(alpha: 0.55),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: cs.onSurfaceVariant,
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class LogViewerLineList extends StatelessWidget {
  const LogViewerLineList({
    required this.lines,
    required this.wrapLines,
    required this.scrollController,
    super.key,
  });

  final List<String> lines;
  final bool wrapLines;
  final ScrollController scrollController;

  static const _singleLineExtent = 21.0;
  static final _cacheExtent = ScrollCacheExtent.pixels(1200);

  @override
  Widget build(BuildContext context) {
    final itemCount = lines.length;

    if (wrapLines) {
      return Scrollbar(
        controller: scrollController,
        thumbVisibility: true,
        child: ListView.builder(
          controller: scrollController,
          scrollCacheExtent: _cacheExtent,
          addAutomaticKeepAlives: false,
          addSemanticIndexes: false,
          itemCount: itemCount,
          itemBuilder: (context, index) {
            return _LogLineTile(
              line: lines[index],
              index: index,
              singleLine: false,
            );
          },
        ),
      );
    }

    return Scrollbar(
      controller: scrollController,
      thumbVisibility: true,
      child: ListView.builder(
        controller: scrollController,
        itemExtent: _singleLineExtent,
        scrollCacheExtent: _cacheExtent,
        addAutomaticKeepAlives: false,
        addSemanticIndexes: false,
        itemCount: itemCount,
        itemBuilder: (context, index) {
          return _LogLineTile(
            line: lines[index],
            index: index,
            singleLine: true,
          );
        },
      ),
    );
  }
}

class _LogLineTile extends StatelessWidget {
  const _LogLineTile({
    required this.line,
    required this.index,
    required this.singleLine,
  });

  final String line;
  final int index;
  final bool singleLine;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tinted = logLineColor(context, line);
    final bg = index.isEven
        ? Colors.transparent
        : cs.onSurface.withValues(alpha: 0.03);

    return ColoredBox(
      color: bg,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
        child: Text(
          line,
          maxLines: singleLine ? 1 : null,
          overflow: singleLine ? TextOverflow.clip : null,
          style: logMonospaceStyle(context, color: tinted),
        ),
      ),
    );
  }
}

class LogViewerBody extends StatelessWidget {
  const LogViewerBody({
    required this.logFiles,
    required this.loading,
    required this.displayedLines,
    required this.wrapLines,
    required this.scrollController,
    super.key,
  });

  final List<String> logFiles;
  final bool loading;
  final List<String> displayedLines;
  final bool wrapLines;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final showPending =
        !AppLogger.instance.getFileLoggerInitialized() && logFiles.isEmpty;

    if (showPending) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Text(
              l10n.logViewerPendingTitle,
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Text(
              l10n.logViewerPendingBody,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: ColoredBox(
              color: cs.workspaceCode,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(12),
                child: SelectableText(
                  AppLogger.instance.getFormattedPendingLogs(),
                  style: logMonospaceStyle(context),
                ),
              ),
            ),
          ),
        ],
      );
    }

    if (logFiles.isEmpty && !loading) {
      return LogViewerCenteredMessage(
        icon: Icons.article_outlined,
        title: l10n.logViewerEmpty,
        subtitle: l10n.logViewerEmptyHint,
      );
    }

    return ColoredBox(
      color: cs.workspaceCode,
      child: LogViewerLineList(
        lines: displayedLines,
        wrapLines: wrapLines,
        scrollController: scrollController,
      ),
    );
  }
}
