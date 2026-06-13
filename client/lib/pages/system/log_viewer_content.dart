import 'package:flutter/material.dart';
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
    required this.loadingMore,
    required this.scrollController,
    super.key,
  });

  final List<String> lines;
  final bool wrapLines;
  final bool loadingMore;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    Widget lineWidget(int index, String line) {
      final tinted = logLineColor(context, line);
      final bg = index.isEven
          ? Colors.transparent
          : cs.onSurface.withValues(alpha: 0.03);
      return ColoredBox(
        color: bg,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
          child: SelectableText(
            line,
            style: logMonospaceStyle(context, color: tinted),
          ),
        ),
      );
    }

    if (wrapLines) {
      return ListView.builder(
        controller: scrollController,
        itemCount: lines.length + (loadingMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= lines.length) {
            return const Padding(
              padding: EdgeInsets.all(20),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            );
          }
          return lineWidget(index, lines[index]);
        },
      );
    }

    return SingleChildScrollView(
      controller: scrollController,
      scrollDirection: Axis.horizontal,
      child: SizedBox(
        width: 2000,
        child: ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: lines.length,
          itemBuilder: (context, index) => lineWidget(index, lines[index]),
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
    required this.loadingMore,
    required this.scrollController,
    super.key,
  });

  final List<String> logFiles;
  final bool loading;
  final List<String> displayedLines;
  final bool wrapLines;
  final bool loadingMore;
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
        loadingMore: loadingMore,
        scrollController: scrollController,
      ),
    );
  }
}
