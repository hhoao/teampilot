import 'package:flutter/foundation.dart';

/// Carries the "scroll to this message" intent from find / the outline rail
/// down to [SessionHistoryThread]. [epoch] lets re-selecting the same message
/// re-trigger the reveal. [animate] uses a smooth scroll instead of [jumpTo].
class ChatRevealController extends ChangeNotifier {
  String? targetMessageId;
  int epoch = 0;
  bool animate = false;

  void reveal(String messageId, {bool animate = false}) {
    targetMessageId = messageId;
    this.animate = animate;
    epoch++;
    notifyListeners();
  }

  void clear() {
    targetMessageId = null;
    animate = false;
    epoch++;
    notifyListeners();
  }
}
