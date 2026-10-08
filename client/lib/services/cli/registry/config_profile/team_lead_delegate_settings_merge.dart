/// Merges team-lead delegate-only PreToolUse hook into Claude Code settings.
class TeamLeadDelegateSettingsMerge {
  const TeamLeadDelegateSettingsMerge();

  /// Pipe-separated PreToolUse matcher (Claude Code hook syntax).
  static const blockedToolsMatcher =
      'Bash|Edit|Write|NotebookEdit|PowerShell|Skill|ExecuteExtraTool|REPL|workflow|EnterWorktree|ExitWorktree|RemoteTrigger|CronCreate';
}
