/// Base hook script names (without `.sh` / `.ps1` extension).
abstract final class TeamPilotHookScripts {
  TeamPilotHookScripts._();

  static const teamLeadSelf = 'teampilot-deny-team-lead-self-message';
  static const teamLeadDelegate = 'teampilot-team-lead-delegate-only';
  static const rtkRewrite = 'rtk-rewrite';
}
