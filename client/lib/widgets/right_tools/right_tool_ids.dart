/// Stable ids for right-tools tabs (open-set / selection), independent of
/// catalog order so shortcuts and persistence survive visibility toggles.
abstract final class RightToolIds {
  static const members = 'members';
  static const fileTree = 'fileTree';
  static const git = 'git';
  static const mailbox = 'mailbox';
  static const board = 'board';
  static const search = 'search';

  /// First-visit open set for mixed-mode team sessions (members / mailbox / board).
  static const mixedTeamDefaults = [members, mailbox, board];
}
