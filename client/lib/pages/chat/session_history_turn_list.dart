import 'package:flutter/material.dart';

import '../../cubits/session_history_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../services/session/session_history_pagination.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import 'session_history_turn_tile.dart';

/// Read-only transcript turns for session history review.
class SessionHistoryTurnList extends StatefulWidget {
  const SessionHistoryTurnList({
    required this.state,
    required this.onRetry,
    this.onLoadOlder,
    super.key,
  });

  final SessionHistoryState state;
  final VoidCallback onRetry;
  final VoidCallback? onLoadOlder;

  @override
  State<SessionHistoryTurnList> createState() => _SessionHistoryTurnListState();
}

class _SessionHistoryTurnListState extends State<SessionHistoryTurnList> {
  final _scrollController = ScrollController();
  double? _scrollExtentBeforeOlderLoad;
  double? _scrollPixelsBeforeOlderLoad;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant SessionHistoryTurnList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.state.status != SessionHistoryViewStatus.ready) return;

    final oldTurns = oldWidget.state.turns;
    final newTurns = widget.state.turns;
    if (newTurns.isEmpty) return;

    final becameReady =
        oldWidget.state.status != SessionHistoryViewStatus.ready;
    final loadedOlder =
        !becameReady &&
        newTurns.length > oldTurns.length &&
        oldTurns.isNotEmpty &&
        newTurns.first.markdown != oldTurns.first.markdown;

    if (!becameReady && !loadedOlder) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      if (becameReady) {
        _scrollToBottomIfOverflow();
        return;
      }
      _restoreScrollAfterOlderLoad();
    });
  }

  void _scrollToBottomIfOverflow() {
    if (!_scrollController.hasClients) return;
    final max = _scrollController.position.maxScrollExtent;
    if (max > 0) {
      _scrollController.jumpTo(max);
    }
  }

  void _restoreScrollAfterOlderLoad() {
    final beforeExtent = _scrollExtentBeforeOlderLoad;
    final beforePixels = _scrollPixelsBeforeOlderLoad;
    _scrollExtentBeforeOlderLoad = null;
    _scrollPixelsBeforeOlderLoad = null;
    if (beforeExtent == null || beforePixels == null) return;
    if (!_scrollController.hasClients) return;

    final delta = _scrollController.position.maxScrollExtent - beforeExtent;
    _scrollController.jumpTo(beforePixels + delta);
  }

  bool _onScroll(ScrollNotification notification) {
    final state = widget.state;
    if (state.status != SessionHistoryViewStatus.ready) return false;
    if (!state.hasOlder || state.isLoadingOlder) return false;
    if (widget.onLoadOlder == null) return false;

    final metrics = notification.metrics;
    if (metrics.pixels > kSessionHistoryLoadOlderScrollThreshold) {
      return false;
    }

    _scrollExtentBeforeOlderLoad = metrics.maxScrollExtent;
    _scrollPixelsBeforeOlderLoad = metrics.pixels;
    widget.onLoadOlder!();
    return false;
  }

  @override
  Widget build(BuildContext context) {
    switch (widget.state.status) {
      case SessionHistoryViewStatus.loading:
        return _HistoryStatusPane(
          icon: Icons.history_rounded,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
              SizedBox(height: context.appSpacing.md),
              Text(
                context.l10n.sessionHistoryLoading,
                style: AppTextStyles.of(context).body.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        );
      case SessionHistoryViewStatus.empty:
        return _HistoryStatusPane(
          icon: Icons.chat_bubble_outline_rounded,
          child: Text(
            context.l10n.sessionHistoryEmpty,
            style: AppTextStyles.of(context).body.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        );
      case SessionHistoryViewStatus.error:
        final detail = widget.state.errorMessage?.trim();
        return _HistoryStatusPane(
          icon: Icons.error_outline_rounded,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                context.l10n.sessionHistoryError,
                style: AppTextStyles.of(context).body.copyWith(
                  color: Theme.of(context).colorScheme.error,
                ),
                textAlign: TextAlign.center,
              ),
              if (detail != null && detail.isNotEmpty) ...[
                SizedBox(height: context.appSpacing.sm),
                Text(
                  detail,
                  style: AppTextStyles.of(context).bodySmall.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
              SizedBox(height: context.appSpacing.md),
              TextButton(
                onPressed: widget.onRetry,
                child: Text(context.l10n.sessionHistoryRetry),
              ),
            ],
          ),
        );
      case SessionHistoryViewStatus.ready:
        final turns = widget.state.turns;
        final sentinelCount = widget.state.hasOlder ? 1 : 0;
        return NotificationListener<ScrollNotification>(
          onNotification: _onScroll,
          child: ListView.builder(
            controller: _scrollController,
            padding: EdgeInsets.fromLTRB(
              context.appSpacing.xl,
              context.appSpacing.md,
              context.appSpacing.xl,
              0,
            ),
            itemCount: turns.length + sentinelCount,
            itemBuilder: (context, index) {
              if (widget.state.hasOlder && index == 0) {
                return _LoadOlderSentinel(
                  isLoading: widget.state.isLoadingOlder,
                );
              }
              final turnIndex = widget.state.hasOlder ? index - 1 : index;
              return SessionHistoryTurnTile(turn: turns[turnIndex]);
            },
          ),
        );
    }
  }
}

class _HistoryStatusPane extends StatelessWidget {
  const _HistoryStatusPane({required this.icon, required this.child});

  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: context.appSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 32, color: cs.onSurfaceVariant.withValues(alpha: 0.55)),
            SizedBox(height: context.appSpacing.md),
            child,
          ],
        ),
      ),
    );
  }
}

class _LoadOlderSentinel extends StatelessWidget {
  const _LoadOlderSentinel({required this.isLoading});

  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final spacing = context.appSpacing;
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: EdgeInsets.only(bottom: spacing.md),
      child: Center(
        child: isLoading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Text(
                context.l10n.sessionHistoryLoadOlderHint,
                style: AppTextStyles.of(context).bodySmall.copyWith(
                  color: cs.onSurfaceVariant.withValues(alpha: 0.75),
                ),
                textAlign: TextAlign.center,
              ),
      ),
    );
  }
}
