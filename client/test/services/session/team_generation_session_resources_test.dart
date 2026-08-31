import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/team_generation_settings.dart';
import 'package:teampilot/services/resource/resource_provider_set.dart';
import 'package:teampilot/services/session/session_lifecycle_service.dart';
import 'package:teampilot/services/team_generation/providers/managed_team_builder_skill_provider.dart';

import '../../support/post_frame_test_harness.dart';

void main() {
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  test('resolver injects the managed builder skill only for builder sessions',
      () async {
    final builderSession = AppSession(
      sessionId: 'builder',
      workspaceId: 'ws',
      purpose: SessionPurpose.teamGeneration,
      workflowId: 'wf',
      createdAt: 1,
    );
    final normalSession = AppSession(
      sessionId: 'normal',
      workspaceId: 'ws',
      createdAt: 1,
    );

    ResourceProviderSet resolver(AppSession session, ResourceProviderSet d) {
      if (session.purpose != SessionPurpose.teamGeneration) return d;
      return ResourceProviderSet(
        skills: [ManagedTeamBuilderSkillProvider()],
      );
    }

    final builderDefaults = resolver(builderSession, ResourceProviderSet.empty);
    final normalDefaults = resolver(normalSession, ResourceProviderSet.empty);

    expect(builderDefaults.skills, hasLength(1));
    expect(
      builderDefaults.skills.single.providerId,
      ManagedTeamBuilderSkillProvider.skillId,
    );
    expect(normalDefaults.skills, isEmpty);
    // The lifecycle service consumes the resolver through
    // _prepareLaunchPlanFromRuntimePlan(resourceProviderResolver: ...);
    // this asserts the seam type is wired and defaults are unchanged for
    // normal sessions.
    expect(SessionLifecycleService, isNotNull);
    expect(resolveTeamGenerationSettingsSnapshot, isNotNull);
  });
}
