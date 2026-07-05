import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/expert_session_overlay.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/expert_hub/expert_member_overlay.dart';

void main() {
  test('applyExpertOverlay replaces prompt and playbook, preserves provider/model',
      () {
    const base = TeamMemberConfig(
      id: 'agent',
      name: 'agent',
      provider: 'anthropic',
      model: 'claude-sonnet-4',
      prompt: 'Base prompt',
      playbook: 'Base playbook',
    );
    const overlay = ExpertSessionOverlay(
      expertKey: 'teampilot/builtin/developer',
      displayName: 'Developer',
      prompt: 'Expert prompt',
      playbook: 'Expert playbook',
    );

    final result = applyExpertOverlay(base, overlay);

    expect(result.name, 'Developer');
    expect(result.prompt, 'Expert prompt');
    expect(result.playbook, 'Expert playbook');
    expect(result.provider, 'anthropic');
    expect(result.model, 'claude-sonnet-4');
    expect(result.id, base.id);
  });

  test('applyExpertOverlay null returns base unchanged', () {
    const base = TeamMemberConfig(
      id: 'agent',
      name: 'agent',
      prompt: 'Base prompt',
    );
    expect(applyExpertOverlay(base, null), base);
  });

  test('applyExpertOverlay skips empty overlay fields', () {
    const base = TeamMemberConfig(
      id: 'agent',
      name: 'agent',
      prompt: 'Base prompt',
      playbook: 'Base playbook',
    );
    const overlay = ExpertSessionOverlay(
      expertKey: 'local/x',
      displayName: '   ',
      prompt: '  ',
      playbook: '',
    );

    final result = applyExpertOverlay(base, overlay);

    expect(result.name, 'agent');
    expect(result.prompt, 'Base prompt');
    expect(result.playbook, 'Base playbook');
  });

  test('ExpertSessionOverlay round-trips JSON', () {
    const overlay = ExpertSessionOverlay(
      expertKey: 'teampilot/builtin/developer',
      displayName: 'Developer',
      prompt: 'You implement features.',
      playbook: 'Use TDD.',
    );
    final decoded = ExpertSessionOverlay.fromJson(overlay.toJson());
    expect(decoded, overlay);
  });

  test('AppSession round-trips expertKey and expertOverlay', () {
    const overlay = ExpertSessionOverlay(
      expertKey: 'teampilot/builtin/developer',
      displayName: 'Developer',
      prompt: 'Expert prompt',
      playbook: 'Expert playbook',
    );
    final session = AppSession(
      sessionId: 's1',
      workspaceId: 'w1',
      createdAt: 1,
      expertKey: overlay.expertKey,
      expertOverlay: overlay,
    );
    final restored = AppSession.fromJson(session.toJson());
    expect(restored.expertKey, overlay.expertKey);
    expect(restored.expertOverlay, overlay);
  });
}
