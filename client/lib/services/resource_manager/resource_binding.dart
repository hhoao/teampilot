/// Stable binding identity for a workspace terminal row in Resource Manager.
enum ResourceBindingKind {
  chatMember,
  workspaceShell,
}

/// In-memory binding for one chat member shell or workspace shell tab.
///
/// Keys follow:
/// - Chat: `chat:{sessionId}:{memberId}`
/// - Shell: `shell:{workspaceId}:{entryId}`
class ResourceBinding {
  const ResourceBinding({
    required this.key,
    required this.kind,
    required this.groupKey,
    required this.groupLabel,
    required this.title,
    required this.connected,
    this.sessionId,
    this.memberId,
    this.workspaceId,
    this.shellEntryId,
    this.livePid,
  });

  final String key;
  final ResourceBindingKind kind;
  final String groupKey;
  final String groupLabel;
  final String title;
  final bool connected;
  final String? sessionId;
  final String? memberId;
  final String? workspaceId;
  final String? shellEntryId;
  final int? livePid;
}
