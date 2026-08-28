import 'dart:async';

import 'package:ai_message_core/ai_message_core.dart';

import 'chat_reveal_controller.dart';

class ChatMessageLocator {
  ChatMessageLocator({
    required this.loadedMessages,
    required this.runtime,
    required this.revealInWindow,
    required this.revealController,
    required this.onHighlight,
    this.timeout = const Duration(milliseconds: 450),
    Future<void> Function()? waitFrame,
  }) : waitFrame = waitFrame ?? (() => Future<void>.value());

  final List<AiMessage> Function() loadedMessages;
  final AiThreadRuntime Function() runtime;
  final void Function(int index) revealInWindow;
  final ChatRevealController revealController;
  final void Function(String? id) onHighlight;
  final Duration timeout;
  final Future<void> Function() waitFrame;

  int _generation = 0;

  void cancel() {
    _generation++;
  }

  /// [index] is accepted for callers but ignored; resolution is by id only.
  /// Pass [highlight] false to scroll without the find-style ring.
  /// Pass [animate] true for a smooth scroll (outline rail); find stays a jump.
  Future<void> locate({
    required String id,
    int? index,
    bool highlight = true,
    bool animate = false,
  }) async {
    final gen = ++_generation;
    final all = loadedMessages();
    final resolved = all.indexWhere((m) => m.id == id);
    if (resolved < 0) return;
    revealInWindow(resolved);
    final rt = runtime();
    if (!_contains(rt, id)) {
      final appeared = Completer<void>();
      final sub = rt.changes.listen((_) {
        if (_contains(rt, id) && !appeared.isCompleted) {
          appeared.complete();
        }
      });
      if (_contains(rt, id) && !appeared.isCompleted) {
        appeared.complete();
      }
      try {
        await appeared.future.timeout(timeout);
      } on TimeoutException {
        return;
      } finally {
        await sub.cancel();
      }
    }
    if (gen != _generation) return;
    await waitFrame();
    if (gen != _generation) return;
    revealController.reveal(id, animate: animate);
    onHighlight(highlight ? id : null);
  }

  bool _contains(AiThreadRuntime rt, String id) {
    for (final m in rt.messages) {
      if (m.id == id) return true;
    }
    return false;
  }
}
