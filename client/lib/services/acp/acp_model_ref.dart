import 'acp_session.dart';

/// Resolves a persisted launch model ref against the ids the open agent
/// advertises.
///
/// The ref may already be a full agent id (`opencode-go/deepseek-v4.1-flash`),
/// a bare id that the agent qualifies itself, or a catalog id whose namespace
/// is unambiguous among [AcpModelState.options]. Returns null when nothing
/// matches, so the caller leaves the agent's current model untouched.
String? acpModelIdForLaunchRef({
  required AcpModelState state,
  required String provider,
  required String model,
  bool allowSuffix = true,
}) {
  final id = model.trim();
  if (id.isEmpty) return null;
  final ids = <String>{for (final option in state.options) option.id};
  if (ids.contains(id)) return id;
  final namespace = provider.trim();
  if (namespace.isNotEmpty) {
    final qualified = '$namespace/$id';
    if (ids.contains(qualified)) return qualified;
  }
  if (!allowSuffix) return null;
  final suffix = ids.where((option) => option.endsWith('/$id')).toSet();
  return suffix.length == 1 ? suffix.single : null;
}

/// Model ref to persist for a pick made under [namespace].
///
/// Catalog ids stay bare unless the same bare id exists in more than one
/// namespace (then the prefix is required to disambiguate). A [catalogModel]
/// false — a typed custom id — always keeps its namespace, because the agent's
/// catalog cannot re-derive it.
String acpPersistedModelRef({
  required AcpModelState? state,
  required String namespace,
  required String model,
  bool catalogModel = true,
}) {
  final id = model.trim();
  final ns = namespace.trim();
  if (id.isEmpty || ns.isEmpty) return id;
  if (!catalogModel) return '$ns/$id';
  final ids = state?.options.map((option) => option.id) ?? const <String>[];
  final matches = ids.where((option) => option == id || option.endsWith('/$id'));
  return matches.length > 1 ? '$ns/$id' : id;
}
