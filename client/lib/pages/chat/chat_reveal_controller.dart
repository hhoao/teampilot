import 'package:flutter/foundation.dart';

/// Carries the "scroll to this message and highlight it" intent from the chat
/// find host down to [SessionHistoryThread]. [epoch] lets re-selecting the
/// same message re-trigger the reveal.
class ChatRevealController extends ChangeNotifier {
  String? targetMessageId;
  int epoch = 0;

  void reveal(String messageId) {
    targetMessageId = messageId;
    epoch++;
    notifyListeners();
  }

  void clear() {
    targetMessageId = null;
    epoch++;
    notifyListeners();
  }
}
