enum ChatMessageRole { user, system, assistantNote }

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.teamId,
    required this.role,
    required this.content,
    required this.createdAt,
    this.memberId = '',
  });

  final String id;
  final String teamId;
  final ChatMessageRole role;
  final String content;
  final DateTime createdAt;
  final String memberId;
}
