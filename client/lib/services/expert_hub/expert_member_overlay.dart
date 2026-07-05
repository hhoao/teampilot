import '../../models/expert_session_overlay.dart';
import '../../models/team_config.dart';

TeamMemberConfig applyExpertOverlay(
  TeamMemberConfig base,
  ExpertSessionOverlay? overlay,
) {
  if (overlay == null) return base;
  final prompt = overlay.prompt.trim();
  final playbook = overlay.playbook.trim();
  return base.copyWith(
    name: overlay.displayName.trim().isNotEmpty
        ? overlay.displayName.trim()
        : base.name,
    prompt: prompt.isNotEmpty ? prompt : base.prompt,
    playbook: playbook.isNotEmpty ? playbook : base.playbook,
  );
}
