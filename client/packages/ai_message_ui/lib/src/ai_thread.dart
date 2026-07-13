import 'dart:async';

import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter/material.dart';

import 'ai_message_view.dart';
import 'message_action_bar.dart';
import 'part_registry.dart';
import 'strings.dart';
import 'theme.dart';

/// Binds an [AiThreadRuntime] and renders status / message list chrome.
///
/// Load-older scroll behavior is owned here (ported from session history
/// turn list). Copy for empty/error/loading is injected via builders — this
/// package does not ship l10n strings.
class AiThread extends StatefulWidget {
  const AiThread({
    required this.runtime,
    required this.loadingBuilder,
    required this.emptyBuilder,
    required this.errorBuilder,
    this.messageBuilder,
    this.registry = AiPartRegistry.defaults,
    this.hasOlder = false,
    this.isLoadingOlder = false,
    this.onLoadOlder,
    this.loadOlderScrollThreshold = 120,
    this.scrollController,
    this.loadOlderHeaderBuilder,
    this.onRetry,
    this.selectionContextMenuBuilder,
    super.key,
  });

  final AiThreadRuntime runtime;
  final Widget Function(BuildContext context) loadingBuilder;
  final Widget Function(BuildContext context) emptyBuilder;
  final Widget Function(
    BuildContext context,
    String? message,
    VoidCallback? onRetry,
  )
  errorBuilder;
  final Widget Function(BuildContext context, AiMessage message)?
  messageBuilder;
  final AiPartRegistry registry;
  final bool hasOlder;
  final bool isLoadingOlder;
  final VoidCallback? onLoadOlder;
  final double loadOlderScrollThreshold;
  final ScrollController? scrollController;
  final Widget Function(BuildContext context, {required bool isLoadingOlder})?
  loadOlderHeaderBuilder;
  final VoidCallback? onRetry;

  /// Replaces the platform [SelectionArea] text toolbar (e.g. app action menu).
  final SelectableRegionContextMenuBuilder? selectionContextMenuBuilder;

  @override
  State<AiThread> createState() => _AiThreadState();
}

class _AiThreadState extends State<AiThread> {
  StreamSubscription<void>? _subscription;
  late ScrollController _scrollController;
  bool _ownsScrollController = false;
  bool _showScrollToBottom = false;

  static const _scrollToBottomThreshold = 80.0;

  List<AiMessage> _messages = const [];
  AiThreadStatus _status = AiThreadStatus.empty;
  String? _errorMessage;

  double? _scrollExtentBeforeOlderLoad;
  double? _scrollPixelsBeforeOlderLoad;

  @override
  void initState() {
    super.initState();
    _attachScrollController(widget.scrollController);
    _syncFromRuntime();
    _subscription = widget.runtime.changes.listen((_) {
      if (!mounted) return;
      final previousStatus = _status;
      final previousMessages = _messages;
      setState(_syncFromRuntime);
      _handleMessagesChanged(
        previousStatus: previousStatus,
        previousMessages: previousMessages,
      );
    });
    // First paint with an already-idle store should still land at the bottom.
    if (_status == AiThreadStatus.idle && _messages.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scrollController.hasClients) return;
        _scrollToBottomIfOverflow();
        _updateScrollToBottomVisibility();
      });
    }
  }

  @override
  void didUpdateWidget(covariant AiThread oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.runtime != widget.runtime) {
      _subscription?.cancel();
      _syncFromRuntime();
      _subscription = widget.runtime.changes.listen((_) {
        if (!mounted) return;
        final previousStatus = _status;
        final previousMessages = _messages;
        setState(_syncFromRuntime);
        _handleMessagesChanged(
          previousStatus: previousStatus,
          previousMessages: previousMessages,
        );
      });
    }
    if (oldWidget.scrollController != widget.scrollController) {
      _detachScrollController();
      _attachScrollController(widget.scrollController);
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _detachScrollController();
    super.dispose();
  }

  void _attachScrollController(ScrollController? external) {
    if (external != null) {
      _scrollController = external;
      _ownsScrollController = false;
    } else {
      _scrollController = ScrollController();
      _ownsScrollController = true;
    }
    _scrollController.addListener(_updateScrollToBottomVisibility);
  }

  void _detachScrollController() {
    _scrollController.removeListener(_updateScrollToBottomVisibility);
    if (_ownsScrollController) {
      _scrollController.dispose();
    }
  }

  void _syncFromRuntime() {
    _messages = widget.runtime.messages;
    _status = widget.runtime.status;
    _errorMessage = widget.runtime.errorMessage;
  }

  void _updateScrollToBottomVisibility() {
    if (!mounted) return;
    if (!_scrollController.hasClients || _status != AiThreadStatus.idle) {
      if (_showScrollToBottom) {
        setState(() => _showScrollToBottom = false);
      }
      return;
    }
    final position = _scrollController.position;
    final distance = position.maxScrollExtent - position.pixels;
    final show =
        position.maxScrollExtent > 0 && distance > _scrollToBottomThreshold;
    if (show != _showScrollToBottom) {
      setState(() => _showScrollToBottom = show);
    }
  }

  Future<void> _animateScrollToBottom() async {
    if (!_scrollController.hasClients) return;
    await _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
    _updateScrollToBottomVisibility();
  }

  void _handleMessagesChanged({
    required AiThreadStatus previousStatus,
    required List<AiMessage> previousMessages,
  }) {
    if (_status != AiThreadStatus.idle || _messages.isEmpty) return;

    final becameIdle =
        previousStatus != AiThreadStatus.idle && _status == AiThreadStatus.idle;
    final loadedOlder =
        !becameIdle &&
        _messages.length > previousMessages.length &&
        previousMessages.isNotEmpty &&
        _messages.first.id != previousMessages.first.id;

    if (!becameIdle && !loadedOlder) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      if (becameIdle) {
        _scrollToBottomIfOverflow();
        _updateScrollToBottomVisibility();
        return;
      }
      _restoreScrollAfterOlderLoad();
      _updateScrollToBottomVisibility();
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
    _updateScrollToBottomVisibility();
    if (_status != AiThreadStatus.idle) return false;
    if (!widget.hasOlder || widget.isLoadingOlder) return false;
    if (widget.onLoadOlder == null) return false;

    final metrics = notification.metrics;
    if (metrics.pixels > widget.loadOlderScrollThreshold) {
      return false;
    }

    _scrollExtentBeforeOlderLoad = metrics.maxScrollExtent;
    _scrollPixelsBeforeOlderLoad = metrics.pixels;
    widget.onLoadOlder!();
    return false;
  }

  Widget _buildMessage(BuildContext context, AiMessage message, {required bool isLast}) {
    final builder = widget.messageBuilder;
    if (builder != null) return builder(context, message);
    return AiMessageView(
      message: message,
      registry: widget.registry,
      actionBarReveal:
          isLast ? AiActionBarReveal.always : AiActionBarReveal.hover,
    );
  }

  Widget _buildLoadOlderHeader(BuildContext context) {
    final builder = widget.loadOlderHeaderBuilder;
    if (builder != null) {
      return builder(context, isLoadingOlder: widget.isLoadingOlder);
    }
    if (widget.isLoadingOlder) {
      return const Padding(
        padding: EdgeInsets.only(bottom: 12),
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _buildScrollToBottomButton(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final strings = AiMessageStrings.of(context);
    return Positioned(
      left: 0,
      right: 0,
      bottom: 8,
      child: Center(
        child: SelectionContainer.disabled(
          child: Material(
            color: scheme.surface,
            shape: CircleBorder(
              side: BorderSide(color: scheme.outlineVariant),
            ),
            elevation: 2,
            shadowColor: Colors.black.withValues(alpha: 0.12),
            child: IconButton(
              tooltip: strings.scrollToBottom,
              onPressed: _animateScrollToBottom,
              icon: Icon(
                Icons.keyboard_arrow_down_rounded,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    switch (_status) {
      case AiThreadStatus.loading:
        return widget.loadingBuilder(context);
      case AiThreadStatus.empty:
        return widget.emptyBuilder(context);
      case AiThreadStatus.error:
        return widget.errorBuilder(context, _errorMessage, widget.onRetry);
      case AiThreadStatus.idle:
        final aiTheme = AiMessageTheme.of(context);
        final sentinelCount = widget.hasOlder ? 1 : 0;
        // One selection region for the thread — markdown/tool Text join into a
        // continuous drag/double-click selection (not per-paragraph islands).
        return SelectionArea(
          contextMenuBuilder: widget.selectionContextMenuBuilder,
          child: Stack(
            children: [
              NotificationListener<ScrollNotification>(
                onNotification: _onScroll,
                child: ListView.builder(
                  controller: _scrollController,
                  // Horizontal inset is applied per-message so empty margins beside
                  // the column still hit-test the scrollable (wheel / drag scroll).
                  padding: const EdgeInsets.fromLTRB(0, 16, 0, 24),
                  itemCount: _messages.length + sentinelCount,
                  itemBuilder: (context, index) {
                    if (widget.hasOlder && index == 0) {
                      return SelectionContainer.disabled(
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: aiTheme.threadHorizontalPadding,
                          ),
                          child: _buildLoadOlderHeader(context),
                        ),
                      );
                    }
                    final messageIndex = widget.hasOlder ? index - 1 : index;
                    final isLast = messageIndex == _messages.length - 1;
                    return Align(
                      alignment: Alignment.topCenter,
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: aiTheme.threadHorizontalPadding,
                        ),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: aiTheme.threadMaxWidth,
                          ),
                          child: _buildMessage(
                            context,
                            _messages[messageIndex],
                            isLast: isLast,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              if (_showScrollToBottom) _buildScrollToBottomButton(context),
            ],
          ),
        );
    }
  }
}
