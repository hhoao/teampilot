import '../models/ssh_profile.dart';
import 'ssh_profile_repository.dart';

/// Read-oriented [SshProfileRepository] for work-plane execution chains
/// (workspace terminals, run/clone SSH spawners, folder target liveness).
///
/// A work-plane target id `ssh:<id>` names a host in the home-plane workload
/// catalog (B source), so [findById] looks there first. The device-local
/// home-binding catalog (A source) is the fallback: it keeps SSH-home mode,
/// offline home binding, and the device-local "+ SSH session" targets
/// resolvable through the same point lookup. This is deliberately a **point
/// lookup** view, not a merge of the two independent catalogs: [loadAll] is
/// B-only so no consumer can accidentally render A + B as one machine list.
/// Machine enumeration belongs to the B-source `RuntimeTargetRegistry`, not
/// here.
///
/// Mutations are unsupported: a caller that edits profiles must go through the
/// owning source repository (device-local A or plane B) directly, so a write
/// can never land in the wrong catalog.
class CombinedSshProfileRepository extends SshProfileRepository {
  CombinedSshProfileRepository({
    required super.storage,
    required SshProfileRepository workload,
    required SshProfileRepository home,
  }) : _workload = workload,
       _home = home;

  final SshProfileRepository _workload;
  final SshProfileRepository _home;

  @override
  Future<SshProfile?> findById(String profileId) async =>
      (await _workload.findById(profileId)) ??
      (await _home.findById(profileId));

  @override
  Future<List<SshProfile>> loadAll() => _workload.loadAll();

  @override
  Future<void> save(SshProfile profile) => _readOnly('save');

  @override
  Future<void> saveAll(List<SshProfile> profiles) => _readOnly('saveAll');

  @override
  Future<void> delete(String profileId) => _readOnly('delete');

  @override
  Future<void> saveSelectedProfileId(String profileId) =>
      _readOnly('saveSelectedProfileId');

  @override
  Future<String> loadSelectedProfileId() async => '';
}

Never _readOnly(String op) => throw UnsupportedError(
  'CombinedSshProfileRepository is a read-only point-lookup view; '
  '$op must go through the owning A- or B-source repository instead',
);
