sealed class MockTurn {
  const MockTurn();
}

final class ToolUseTurn extends MockTurn {
  const ToolUseTurn({required this.id, required this.name, required this.input});
  final String id;
  final String name;
  final Map<String, Object?> input;
}

final class TextTurn extends MockTurn {
  const TextTurn(this.text);
  final String text;
}

class MockScenario {
  const MockScenario({required this.turns});
  final List<MockTurn> turns;
}

class ScenarioRegistry {
  ScenarioRegistry(Map<String, MockScenario> scenarios)
      : _scenarios = Map.unmodifiable(scenarios),
        _indices = {for (final k in scenarios.keys) k: 0};

  final Map<String, MockScenario> _scenarios;
  final Map<String, int> _indices;

  Iterable<String> get keys => _scenarios.keys;

  MockScenario? scenarioFor(String apiKey) => _scenarios[apiKey];

  /// Index of the next scripted turn (before [nextTurn] advances).
  int peekTurnIndex(String apiKey) => _indices[apiKey] ?? 0;

  MockTurn nextTurn(String apiKey) {
    final scenario = _scenarios[apiKey];
    if (scenario == null) throw StateError('unknown api key: $apiKey');
    final i = _indices[apiKey] ?? 0;
    if (i >= scenario.turns.length) {
      throw StateError('scenario exhausted for $apiKey at turn $i');
    }
    _indices[apiKey] = i + 1;
    return scenario.turns[i];
  }

  static String describeTurn(MockTurn turn) => switch (turn) {
        ToolUseTurn(:final id, :final name) => 'tool:$name id=$id',
        TextTurn(:final text) =>
          'text:${text.length > 48 ? '${text.substring(0, 48)}…' : text}',
      };

  void reset() {
    for (final k in _scenarios.keys) {
      _indices[k] = 0;
    }
  }
}
