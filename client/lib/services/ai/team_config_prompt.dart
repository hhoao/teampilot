import '../../models/team_config.dart';
import 'team_config_prompt_mixed.dart';
import 'team_config_prompt_native.dart';

/// Dispatches to the mode-specific engineering-grade team prompt builder.
///
/// The user [description] is interpolated unescaped. Acceptable: it is a
/// local-only desktop feature, the user authored the text, and the draft is
/// shown for review before a team is created. Generation produces only the team
/// shape and prose; model/effort/skills/cli are configured by the user later.
String buildTeamConfigPrompt({
  required TeamMode mode,
  required String description,
}) {
  return switch (mode) {
    TeamMode.native => buildNativeTeamConfigPrompt(description: description),
    TeamMode.mixed => buildMixedTeamConfigPrompt(description: description),
  };
}
