import '../core/turns.dart';

/// Actor apiKey for the simple-mode seat in L2 matrix cells.
const simpleScriptApiKey = 'simple-script';

/// Stable PTY / bubble markers for [simple3TurnScenarios].
const markA1 = 'MARK_A1';
const markA2 = 'MARK_A2';
const markA3 = 'MARK_A3';

/// Simple-mode recipe: three assistant [TextTurn]s with distinct markers.
///
/// L2 History compose targets the single simple seat (`simple-script`).
Map<String, MockScenario> simple3TurnScenarios() => {
      simpleScriptApiKey: MockScenario(
        turns: [
          TextTurn(markA1),
          TextTurn(markA2),
          TextTurn(markA3),
        ],
      ),
    };
