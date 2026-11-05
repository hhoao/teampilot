import '../../models/vault_reference.dart';

/// Produces the owners that reference a vault entry.
typedef VaultReferenceSource =
    Future<List<VaultReference>> Function(String entryId);

/// Aggregates reference sources (SSH, app providers, managed providers,
/// GitHub) behind one extension point.
///
/// Adding a new credential owner means adding one source in `AppShell`; the
/// vault cubit and UI do not change.
class VaultReferenceIndexer {
  VaultReferenceIndexer(List<VaultReferenceSource> sources)
    : _sources = List.unmodifiable(sources);

  final List<VaultReferenceSource> _sources;

  Future<List<VaultReference>> referencesTo(String entryId) async {
    final results = await Future.wait(
      _sources.map((source) => source(entryId)),
    );
    return [for (final references in results) ...references];
  }
}
