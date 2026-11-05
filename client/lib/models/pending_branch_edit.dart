/// An edited user message shown in place until its new turn lands.
///
/// This is transient UI state, not part of the rewind read model: the cubit
/// owns it so a reconnect/rebuild cannot drop the optimistic bubble.
final class PendingBranchEdit {
  const PendingBranchEdit({required this.messageId, required this.text});

  final String messageId;
  final String text;
}
