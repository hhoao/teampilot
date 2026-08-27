import 'package:ai_message_core/ai_message_core.dart';
import 'package:ai_message_ui/ai_message_ui.dart';

const int kChatOutlinePreviewLimit = 160;

final RegExp _whitespaceCollapse = RegExp(r'\s+');

enum ChatOutlineKind { userTurn }

class ChatOutlineChrome {
  const ChatOutlineChrome({this.worked, this.gitSha});

  final Duration? worked;
  final String? gitSha;
}

class ChatOutlineEntry {
  const ChatOutlineEntry({
    required this.id,
    required this.messageIndex,
    required this.preview,
    this.kind = ChatOutlineKind.userTurn,
    this.chrome = const ChatOutlineChrome(),
  });

  final String id;
  final int messageIndex;
  final String preview;
  final ChatOutlineKind kind;
  final ChatOutlineChrome chrome;
}

List<ChatOutlineEntry> buildChatOutline(
  List<AiMessage> all, {
  required String emptyPreview,
  List<ChatOutlineEntry> previous = const [],
}) {
  final users = <({int index, AiMessage message})>[];
  for (var i = 0; i < all.length; i++) {
    if (all[i].role == AiRole.user) {
      users.add((index: i, message: all[i]));
    }
  }
  var reuse = 0;
  while (reuse < previous.length &&
      reuse < users.length &&
      previous[reuse].id == users[reuse].message.id &&
      previous[reuse].messageIndex == users[reuse].index &&
      previous[reuse].preview ==
          _previewFor(users[reuse].message, emptyPreview)) {
    reuse++;
  }
  if (reuse == previous.length && reuse == users.length) {
    return previous;
  }
  return [
    ...previous.take(reuse),
    for (var i = reuse; i < users.length; i++)
      ChatOutlineEntry(
        id: users[i].message.id,
        messageIndex: users[i].index,
        preview: _previewFor(users[i].message, emptyPreview),
      ),
  ];
}

String? owningUserTurnId(List<AiMessage> messages, int firstVisibleTurnIndex) {
  if (firstVisibleTurnIndex < 0) return null;
  final turns = buildTurns(messages);
  if (firstVisibleTurnIndex >= turns.length) return null;
  final id = turns[firstVisibleTurnIndex].id;
  for (final m in messages) {
    if (m.id == id) {
      return m.role == AiRole.user ? id : null;
    }
  }
  return null;
}

bool shouldShowChatOutline({
  required bool threadVisible,
  required bool subagentPreviewOpen,
  required List<ChatOutlineEntry> entries,
}) {
  return threadVisible && !subagentPreviewOpen && entries.isNotEmpty;
}

String _previewFor(AiMessage message, String emptyPreview) {
  final buf = StringBuffer();
  for (final part in message.parts) {
    if (part is! AiTextPart) continue;
    final t = part.text.trim();
    if (t.isEmpty) continue;
    if (buf.isNotEmpty) buf.write(' ');
    buf.write(t.replaceAll(_whitespaceCollapse, ' '));
  }
  var text = buf.toString().trim();
  if (text.isEmpty) return emptyPreview;
  if (text.length > kChatOutlinePreviewLimit) {
    text = text.substring(0, kChatOutlinePreviewLimit);
  }
  return text;
}
