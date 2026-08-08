import '../cli_capability.dart';

/// Declares a CLI's "turn ended" signals, driving reliable session
/// working-state clearing (see 2026-08-08-turn-completion-working-clear-design.md).
abstract interface class TurnCompletionCapability implements CliCapability {
  /// Agent-status hook event names that mean "turn ended" (→ done).
  Set<String> get doneEventNames;

  /// Whether the PTY-quiet turn-end fallback may clear the seat
  /// (done event may be unreliable for this CLI).
  bool get requiresPtyFallback;

  /// Whether this is a doorbell-push CLI (mixed mode: `/idle` must end the
  /// bus turn).
  bool get usesDoorbellPush;
}
