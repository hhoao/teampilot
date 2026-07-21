/// Scripted mock-model turn (protocol-agnostic).
///
/// Tool calls use logical [ToolUseTurn.toolRef] / [AssignedTaskUpdateTurn.toolRef];
/// wire names are applied later via [ScenarioEngine.nextResolvedTurn].
sealed class MockTurn {
  const MockTurn();
}

final class TextTurn extends MockTurn {
  const TextTurn(this.text);
  final String text;
}

final class ToolUseTurn extends MockTurn {
  const ToolUseTurn({
    required this.id,
    required this.toolRef,
    required this.input,
  });

  final String id;
  final String toolRef;
  final Map<String, Object?> input;
}

/// Scripts a task-status update using a logical [toolRef].
///
/// The concrete task id may be resolved from an inbound tool_result by the
/// gateway server (same role as mock_anthropic's AssignedTaskUpdateTurn).
final class AssignedTaskUpdateTurn extends MockTurn {
  const AssignedTaskUpdateTurn({
    required this.id,
    required this.toolRef,
    required this.status,
    this.result,
  });

  final String id;
  final String toolRef;
  final String status;
  final String? result;
}

/// Actor-keyed list of scripted turns.
class MockScenario {
  const MockScenario({required this.turns});
  final List<MockTurn> turns;
}

/// Turn with logical tool refs already mapped to on-wire names.
sealed class ResolvedTurn {
  const ResolvedTurn();
}

final class ResolvedTextTurn extends ResolvedTurn {
  const ResolvedTextTurn(this.text);
  final String text;
}

final class ResolvedToolUseTurn extends ResolvedTurn {
  const ResolvedToolUseTurn({
    required this.id,
    required this.wireName,
    required this.input,
  });

  final String id;
  final String wireName;
  final Map<String, Object?> input;
}

final class ResolvedAssignedTaskUpdateTurn extends ResolvedTurn {
  const ResolvedAssignedTaskUpdateTurn({
    required this.id,
    required this.wireName,
    required this.status,
    this.result,
  });

  final String id;
  final String wireName;
  final String status;
  final String? result;
}
