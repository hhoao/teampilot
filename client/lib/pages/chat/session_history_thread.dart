import 'dart:async';

import 'package:ai_message_core/ai_message_core.dart';
import 'package:ai_message_ui/ai_message_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:flutter_chat_ui/flutter_chat_ui.dart';

import 'ai_thread_selection_context_menu.dart';

const _kFlyerUserId = 'user';
const _kFlyerAssistantId = 'assistant';
const _kFlyerSystemId = 'system';

/// History message list backed by Flyer [ChatAnimatedList] + [AiMessageView].
class SessionHistoryThread extends StatefulWidget {
  const SessionHistoryThread({
    required this.runtime,
    required this.hasOlder,
    required this.isLoadingOlder,
    this.onLoadOlder,
    super.key,
  });

  final AiThreadRuntime runtime;
  final bool hasOlder;
  final bool isLoadingOlder;
  final VoidCallback? onLoadOlder;

  @override
  State<SessionHistoryThread> createState() => _SessionHistoryThreadState();
}

class _SessionHistoryThreadState extends State<SessionHistoryThread> {
  late final InMemoryChatController _chatController;
  StreamSubscription<void>? _runtimeSub;
  var _syncing = false;

  @override
  void initState() {
    super.initState();
    _chatController = InMemoryChatController(
      messages: _toFlyerMessages(widget.runtime.messages),
    );
    _runtimeSub = widget.runtime.changes.listen((_) => _syncFromRuntime());
  }

  @override
  void didUpdateWidget(covariant SessionHistoryThread oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.runtime != widget.runtime) {
      _runtimeSub?.cancel();
      _runtimeSub = widget.runtime.changes.listen((_) => _syncFromRuntime());
      unawaited(_syncFromRuntime());
    }
  }

  @override
  void dispose() {
    _runtimeSub?.cancel();
    _chatController.dispose();
    super.dispose();
  }

  Future<void> _syncFromRuntime() async {
    if (_syncing) return;
    _syncing = true;
    try {
      await _chatController.setMessages(
        _toFlyerMessages(widget.runtime.messages),
        animated: false,
      );
    } finally {
      _syncing = false;
    }
  }

  static List<Message> _toFlyerMessages(List<AiMessage> messages) {
    return [
      for (final message in messages)
        Message.custom(
          id: message.id,
          authorId: switch (message.role) {
            AiRole.user => _kFlyerUserId,
            AiRole.assistant => _kFlyerAssistantId,
            AiRole.system => _kFlyerSystemId,
          },
        ),
    ];
  }

  Future<User?> _resolveUser(UserID id) async {
    return User(
      id: id,
      name: switch (id) {
        _kFlyerUserId => 'You',
        _kFlyerAssistantId => 'Assistant',
        _kFlyerSystemId => 'System',
        _ => id,
      },
    );
  }

  Future<void> _onLoadOlder() async {
    if (!widget.hasOlder || widget.isLoadingOlder) return;
    widget.onLoadOlder?.call();
  }

  @override
  Widget build(BuildContext context) {
    final byId = {for (final m in widget.runtime.messages) m.id: m};
    final lastId = widget.runtime.messages.isEmpty
        ? null
        : widget.runtime.messages.last.id;
    final aiTheme = AiMessageTheme.of(context);

    return SelectionArea(
      contextMenuBuilder: buildAiThreadSelectionContextMenu,
      child: Chat(
        currentUserId: _kFlyerUserId,
        resolveUser: _resolveUser,
        chatController: _chatController,
        backgroundColor: Colors.transparent,
        theme: ChatTheme.fromThemeData(Theme.of(context)),
        builders: Builders(
          composerBuilder: (_) => const SizedBox.shrink(),
          scrollToBottomBuilder: (_, __, ___) => const SizedBox.shrink(),
          // Skip Flyer bubble chrome — AiMessageView already owns layout.
          chatMessageBuilder:
              (
                context,
                message,
                index,
                animation,
                child, {
                bool? isRemoved,
                required bool isSentByMe,
                MessageGroupStatus? groupStatus,
              }) =>
                  child,
          chatAnimatedListBuilder: (context, itemBuilder) {
            return ChatAnimatedList(
              itemBuilder: itemBuilder,
              initialScrollToEndMode: InitialScrollToEndMode.jump,
              shouldScrollToEndWhenSendingMessage: false,
              shouldScrollToEndWhenAtBottom: false,
              insertAnimationDuration: Duration.zero,
              removeAnimationDuration: Duration.zero,
              handleSafeArea: false,
              bottomPadding: 8,
              // Non-reversed list: onEndReached = near top (older messages).
              onEndReached: widget.hasOlder ? _onLoadOlder : null,
              topSliver: widget.isLoadingOlder
                  ? const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.only(bottom: 12),
                        child: Center(
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      ),
                    )
                  : null,
            );
          },
          customMessageBuilder:
              (
                context,
                message,
                index, {
                required bool isSentByMe,
                MessageGroupStatus? groupStatus,
              }) {
                final ai = byId[message.id];
                if (ai == null) {
                  return const SizedBox.shrink();
                }
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
                      child: AiMessageView(
                        key: ValueKey(ai.id),
                        message: ai,
                        actionBarReveal: ai.id == lastId
                            ? AiActionBarReveal.always
                            : AiActionBarReveal.hover,
                      ),
                    ),
                  ),
                );
              },
        ),
      ),
    );
  }
}
