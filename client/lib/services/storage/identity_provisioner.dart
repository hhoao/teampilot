import 'package:collection/collection.dart';

import '../../models/personal_identity.dart';
import '../../repositories/identity_repository.dart';

/// Ensures a fresh store always has at least one personal identity, so the
/// simple/open-with path always has a target. Initialization, not migration.
class IdentityProvisioner {
  IdentityProvisioner({required IdentityRepository repository})
      : _repository = repository;

  static const defaultPersonalId = 'personal-default';

  final IdentityRepository _repository;

  Future<PersonalIdentity> ensureDefaultPersonal() async {
    final all = await _repository.loadAll();
    final existing = all
        .whereType<PersonalIdentity>()
        .where((p) => p.id == defaultPersonalId)
        .firstOrNull;
    if (existing != null) return existing;

    final defaultIdentity = PersonalIdentity(
      id: defaultPersonalId,
      display: 'Personal',
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
    await _repository.save(defaultIdentity);
    return defaultIdentity;
  }
}
