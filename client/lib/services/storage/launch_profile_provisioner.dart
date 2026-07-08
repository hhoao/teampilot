import 'package:collection/collection.dart';

import '../../models/launch_profile.dart';
import '../../models/personal_profile.dart';
import '../../models/team_config.dart';
import '../../repositories/launch_profile_repository.dart';

/// Built-in launch identities provisioned on first load. Initialization only —
/// not migration from legacy stores.
class LaunchProfileProvisioner {
  LaunchProfileProvisioner({required LaunchProfileRepository repository})
    : _repository = repository;

  static const defaultPersonalId = 'personal-default';
  static const defaultNativeTeamId = 'default-native-team';
  static const defaultMixedTeamId = 'default-mixed-team';

  static const builtInTeamIds = {
    defaultNativeTeamId,
    defaultMixedTeamId,
  };

  static bool isBuiltInTeamId(String id) => builtInTeamIds.contains(id);

  final LaunchProfileRepository _repository;

  Future<PersonalProfile> ensureDefaultPersonal({
    List<LaunchProfile>? loaded,
  }) async {
    final all = loaded ?? await _repository.loadAll();
    final existing = all
        .whereType<PersonalProfile>()
        .where((p) => p.id == defaultPersonalId)
        .firstOrNull;
    if (existing != null) return existing;

    final defaultIdentity = PersonalProfile(
      id: defaultPersonalId,
      display: 'Personal',
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
    await _repository.save(defaultIdentity);
    return defaultIdentity;
  }

  /// Ensures both built-in team identities exist. [buildNative] / [buildMixed]
  /// are invoked only when the corresponding profile is missing from storage.
  Future<({TeamProfile native, TeamProfile mixed})> ensureDefaultTeams({
    required TeamProfile Function() buildNative,
    required TeamProfile Function() buildMixed,
    List<LaunchProfile>? loaded,
  }) async {
    final all = loaded ?? await _repository.loadAll();
    final existing = all.whereType<TeamProfile>();

    var native = existing
        .where((t) => t.id == defaultNativeTeamId)
        .firstOrNull;
    if (native == null) {
      native = buildNative();
      await _repository.save(native);
    }

    var mixed = existing.where((t) => t.id == defaultMixedTeamId).firstOrNull;
    if (mixed == null) {
      mixed = buildMixed();
      await _repository.save(mixed);
    }

    return (native: native, mixed: mixed);
  }
}
