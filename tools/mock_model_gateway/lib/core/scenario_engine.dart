import 'tool_name_resolver.dart';
import 'turns.dart';

/// Actor-keyed scenario runner with per-actor turn indices.
///
/// Exhaustion and unknown actors throw [StateError] so matrix tests fail loudly.
class ScenarioEngine {
  ScenarioEngine(
    Map<String, MockScenario> scenarios, {
    ToolNameResolver? toolNames,
  })  : _scenarios = Map.unmodifiable(scenarios),
        _indices = {for (final k in scenarios.keys) k: 0},
        _toolNames = toolNames ?? _identityToolNames;

  final Map<String, MockScenario> _scenarios;
  final Map<String, int> _indices;
  final ToolNameResolver _toolNames;

  static String _identityToolNames(String toolRef) => toolRef;

  Iterable<String> get keys => _scenarios.keys;

  MockScenario? scenarioFor(String actorId) => _scenarios[actorId];

  /// Index of the next scripted turn (before [nextTurn] advances).
  int peekTurnIndex(String actorId) => _indices[actorId] ?? 0;

  MockTurn nextTurn(String actorId) {
    final scenario = _scenarios[actorId];
    if (scenario == null) {
      throw StateError('unknown actor: $actorId');
    }
    final i = _indices[actorId] ?? 0;
    if (i >= scenario.turns.length) {
      throw StateError('scenario exhausted for $actorId at turn $i');
    }
    _indices[actorId] = i + 1;
    return scenario.turns[i];
  }

  /// Advances like [nextTurn], resolving logical `toolRef` to on-wire names.
  ResolvedTurn nextResolvedTurn(String actorId) {
    final turn = nextTurn(actorId);
    return switch (turn) {
      TextTurn(:final text) => ResolvedTextTurn(text),
      ToolUseTurn(:final id, :final toolRef, :final input) =>
        ResolvedToolUseTurn(
          id: id,
          wireName: _toolNames(toolRef),
          input: input,
        ),
      AssignedTaskUpdateTurn(
        :final id,
        :final toolRef,
        :final status,
        :final result,
      ) =>
        ResolvedAssignedTaskUpdateTurn(
          id: id,
          wireName: _toolNames(toolRef),
          status: status,
          result: result,
        ),
    };
  }

  static String describeTurn(MockTurn turn) => switch (turn) {
        ToolUseTurn(:final id, :final toolRef) => 'tool:$toolRef id=$id',
        AssignedTaskUpdateTurn(:final id, :final toolRef, :final status) =>
          'update:$toolRef id=$id status=$status',
        TextTurn(:final text) =>
          'text:${text.length > 48 ? '${text.substring(0, 48)}…' : text}',
      };

  void reset() {
    for (final k in _scenarios.keys) {
      _indices[k] = 0;
    }
  }

  /// Resets one actor's turn index without touching other seats.
  ///
  /// Mixed-matrix park+compose must rewind the lead after idle-announce
  /// doorbell traffic without also rewinding a worker already parked on
  /// `wait_for_message` — a full [reset] would re-serve turn 0 and strand
  /// the worker on a second wait until MCP cancel (~120s).
  void resetActor(String actorId) {
    if (!_scenarios.containsKey(actorId)) {
      throw StateError('unknown actor: $actorId');
    }
    _indices[actorId] = 0;
  }

  /// Sets the next [nextTurn] index for one actor (matrix rewind mid-scenario).
  void seekActor(String actorId, int turnIndex) {
    final scenario = _scenarios[actorId];
    if (scenario == null) {
      throw StateError('unknown actor: $actorId');
    }
    if (turnIndex < 0 || turnIndex > scenario.turns.length) {
      throw StateError(
        'turnIndex $turnIndex out of range for $actorId '
        '(turns=${scenario.turns.length})',
      );
    }
    _indices[actorId] = turnIndex;
  }
}
