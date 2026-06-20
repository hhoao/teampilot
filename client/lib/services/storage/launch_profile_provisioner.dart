import 'package:collection/collection.dart';

import '../../models/personal_profile.dart';
import '../../repositories/launch_profile_repository.dart';

/// Ensures a fresh store always has at least one personal identity, so the
/// simple/open-with path always has a target. Initialization, not migration.
class LaunchProfileProvisioner {
  LaunchProfileProvisioner({required LaunchProfileRepository repository})
      : _repository = repository;

  static const defaultPersonalId = 'personal-default';
  static const defaultTeamId = 'default-team';

  final LaunchProfileRepository _repository;

  Future<PersonalProfile> ensureDefaultPersonal() async {
    final all = await _repository.loadAll();
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
}
