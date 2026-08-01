import 'dart:async';

import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'ai_message_view.dart';
import 'message_action_bar.dart';
import 'part_registry.dart';
import 'selection_height_style.dart';
import 'strings.dart';
import 'theme.dart';

/// Binds an [AiThreadRuntime] and renders status / message list chrome.
///
/// Scroll model mirrors assistant-ui `useThreadViewportAutoScroll`:
/// chronologically ordered (non-reverse) list, plant a stick-to-bottom intent
/// on initialize, re-stick when content grows while intent is active, and
/// release intent when the user scrolls up. The list stays invisible until the
/// first stick completes so open does not flash the top of the thread.
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

  /// assistant-ui `scrollingToBottomBehaviorRef` equivalent.
  bool _stickIntent = false;

  /// Hide until first stick so open never paints the thread top.
  bool _listVisible = false;

  int _stickGeneration = 0;
  int _atBottomStableFrames = 0;
  double _lastPixels = 0;
  double _lastMaxExtent = 0;

  double? _scrollExtentBeforeOlderLoad;
  double? _scrollPixelsBeforeOlderLoad;

  static const _bottomEpsilon = 2.0;
  static const _scrollToBottomThreshold = 80.0;
  static const _maxStickFrames = 24;

  List<AiMessage> _messages = const [];
  AiThreadStatus _status = AiThreadStatus.empty;
  String? _errorMessage;

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
    if (_status == AiThreadStatus.idle && _messages.isNotEmpty) {
      _plantStickIntent(hideUntilStuck: true);
    } else if (_status == AiThreadStatus.idle) {
      _listVisible = true;
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
      if (_status == AiThreadStatus.idle && _messages.isNotEmpty) {
        _plantStickIntent(hideUntilStuck: true);
      }
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
    _scrollController.addListener(_onScrollControllerTick);
  }

  void _detachScrollController() {
    _scrollController.removeListener(_onScrollControllerTick);
    if (_ownsScrollController) {
      _scrollController.dispose();
    }
  }

  void _syncFromRuntime() {
    _messages = widget.runtime.messages;
    _status = widget.runtime.status;
    _errorMessage = widget.runtime.errorMessage;
  }

  void _onScrollControllerTick() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    _observeScroll(
      pixels: position.pixels,
      maxExtent: position.maxScrollExtent,
    );
  }

  void _plantStickIntent({required bool hideUntilStuck}) {
    _stickGeneration++;
    final generation = _stickGeneration;
    _stickIntent = true;
    _atBottomStableFrames = 0;
    if (hideUntilStuck && _listVisible) {
      setState(() => _listVisible = false);
    } else if (hideUntilStuck) {
      _listVisible = false;
    }
    _scheduleStickTick(generation: generation, framesLeft: _maxStickFrames);
  }

  void _releaseStickIntent() {
    _stickIntent = false;
    _stickGeneration++;
  }

  void _scheduleStickTick({
    required int generation,
    required int framesLeft,
  }) {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted || generation != _stickGeneration) return;
      _stickToBottomIfNeeded();
      if (!_stickIntent) return;

      final atBottom = _isAtBottom();
      if (atBottom) {
        _atBottomStableFrames++;
      } else {
        _atBottomStableFrames = 0;
      }

      if (!_listVisible) {
        final canReveal = _atBottomStableFrames >= 2 || framesLeft <= 0;
        if (canReveal) {
          setState(() => _listVisible = true);
          _updateScrollToBottomVisibility();
          return;
        }
        _scheduleStickTick(
          generation: generation,
          framesLeft: framesLeft - 1,
        );
        return;
      }

      // Keep ticking briefly after reveal so deferred markdown growth sticks.
      if (!atBottom && framesLeft > 0) {
        _scheduleStickTick(
          generation: generation,
          framesLeft: framesLeft - 1,
        );
      }
    });
  }

  bool _isAtBottom() {
    if (!_scrollController.hasClients) return false;
    final position = _scrollController.position;
    if (position.maxScrollExtent <= 0) return true;
    return position.maxScrollExtent - position.pixels <= _bottomEpsilon;
  }

  void _stickToBottomIfNeeded() {
    if (!_stickIntent || !_scrollController.hasClients) return;
    final position = _scrollController.position;
    final max = position.maxScrollExtent;
    if (max > 0 && max - position.pixels > _bottomEpsilon) {
      _scrollController.jumpTo(max);
    }
    if (_scrollController.hasClients) {
      _lastPixels = _scrollController.position.pixels;
      _lastMaxExtent = _scrollController.position.maxScrollExtent;
    }
  }

  void _observeScroll({
    required double pixels,
    required double maxExtent,
  }) {
    // Scroll-up with stable extent → release stick (aui handleScroll).
    // Covers user drag and programmatic jumpTo away from bottom.
    if (_listVisible &&
        _stickIntent &&
        pixels < _lastPixels - _bottomEpsilon &&
        (maxExtent - _lastMaxExtent).abs() <= _bottomEpsilon) {
      _releaseStickIntent();
    }

    if (_stickIntent && maxExtent > 0 && maxExtent - pixels > _bottomEpsilon) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(maxExtent);
        pixels = _scrollController.position.pixels;
        maxExtent = _scrollController.position.maxScrollExtent;
      }
    }

    _lastPixels = pixels;
    _lastMaxExtent = maxExtent;
    _updateScrollToBottomVisibility();
  }

  void _updateScrollToBottomVisibility() {
    if (!mounted) return;
    if (!_scrollController.hasClients ||
        _status != AiThreadStatus.idle ||
        !_listVisible) {
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
    _plantStickIntent(hideUntilStuck: false);
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
    if (_status != AiThreadStatus.idle) {
      _listVisible = _status != AiThreadStatus.loading;
      return;
    }

    if (_messages.isEmpty) {
      if (!_listVisible) {
        setState(() => _listVisible = true);
      }
      _releaseStickIntent();
      return;
    }

    final becameIdle =
        previousStatus != AiThreadStatus.idle && _status == AiThreadStatus.idle;
    final loadedOlder =
        !becameIdle &&
        _messages.length > previousMessages.length &&
        previousMessages.isNotEmpty &&
        _messages.first.id != previousMessages.first.id;

    if (becameIdle) {
      _plantStickIntent(hideUntilStuck: true);
      return;
    }
    if (!loadedOlder) return;

    // Load-older must not fight stick-to-bottom.
    _releaseStickIntent();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _restoreScrollAfterOlderLoad();
      _updateScrollToBottomVisibility();
    });
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
    _lastPixels = _scrollController.position.pixels;
    _lastMaxExtent = _scrollController.position.maxScrollExtent;
  }

  bool _onScroll(ScrollNotification notification) {
    final metrics = notification.metrics;

    if (notification is ScrollMetricsNotification ||
        notification is ScrollUpdateNotification ||
        notification is UserScrollNotification) {
      _observeScroll(
        pixels: metrics.pixels,
        maxExtent: metrics.maxScrollExtent,
      );
    }

    if (_status != AiThreadStatus.idle) return false;
    if (!widget.hasOlder || widget.isLoadingOlder) return false;
    if (widget.onLoadOlder == null) return false;
    if (metrics.pixels > widget.loadOlderScrollThreshold) return false;

    _scrollExtentBeforeOlderLoad = metrics.maxScrollExtent;
    _scrollPixelsBeforeOlderLoad = metrics.pixels;
    widget.onLoadOlder!();
    return false;
  }

  Widget _buildMessage(
    BuildContext context,
    AiMessage message, {
    required bool isLast,
  }) {
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
        return AiLineSpacedSelectionStyle(
          child: SelectionArea(
          contextMenuBuilder: widget.selectionContextMenuBuilder,
          child: Stack(
            children: [
              NotificationListener<ScrollNotification>(
                onNotification: _onScroll,
                child: Opacity(
                  key: const ValueKey('ai-thread-list-opacity'),
                  opacity: _listVisible ? 1 : 0,
                  child: IgnorePointer(
                    ignoring: !_listVisible,
                    child: ListView.builder(
                      controller: _scrollController,
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
                        final messageIndex =
                            widget.hasOlder ? index - 1 : index;
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
                ),
              ),
              if (_showScrollToBottom && _listVisible)
                _buildScrollToBottomButton(context),
            ],
          ),
          ),
        );
    }
  }
}
