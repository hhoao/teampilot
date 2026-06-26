import '../../models/app_session.dart';
import '../../models/workspace.dart';
import '../../services/cli/registry/config_profile/config_profile_context.dart';
import '../../services/session/session_lifecycle_service.dart';
import '../../services/storage/launch_profile_provisioner.dart';
import 'personal_launch_context.dart';

/// Dedupes in-flight personal launch context resolution within a single turn.
class PersonalLaunchContextResolver {
  PersonalLaunchContextResolver(this._lifecycle);

  final SessionLifecycleService _lifecycle;
  final Map<String, Future<PersonalLaunchContext>> _inflight = {};

  void invalidate() => _inflight.clear();

  Future<PersonalLaunchContext> resolve({
    required AppSession session,
    required Workspace workspace,
    String personalIdentityIdOverride = '',
  }) {
    final key =
        '${session.sessionId}:${personalIdentityIdOverride.trim()}:${workspace.workspaceId}';
    return _inflight.putIfAbsent(key, () async {
      try {
        return await _resolveUncached(
          session: session,
          workspace: workspace,
          personalIdentityIdOverride: personalIdentityIdOverride,
        );
      } finally {
        _inflight.remove(key);
      }
    });
  }

  Future<PersonalLaunchContext> _resolveUncached({
    required AppSession session,
    required Workspace workspace,
    String personalIdentityIdOverride = '',
  }) async {
    var profileId = personalIdentityIdOverride.trim();
    if (profileId.isEmpty) {
      profileId = session.profileId.trim();
    }
    if (profileId.isEmpty) {
      profileId = workspace.defaultProfileId.trim();
    }
    if (profileId.isEmpty) {
      profileId = LaunchProfileProvisioner.defaultPersonalId;
    } else if (await _lifecycle.loadIdentity(profileId) == null) {
      profileId = LaunchProfileProvisioner.defaultPersonalId;
    }
    final personalIdentity = await _lifecycle.loadPersonalProfile(profileId);
    final personalPreset = await _lifecycle.resolveActivePresetForPersonal(
      personalIdentity,
    );
    final personalMember = standaloneMemberFromPersonal(
      personalIdentity,
      preset: personalPreset,
    );
    return PersonalLaunchContext(
      personalIdentity: personalIdentity,
      personalPreset: personalPreset,
      personalMember: personalMember,
    );
  }
}
