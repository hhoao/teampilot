import '../../models/team_config.dart';
import '../agent_runtime/runtime_event.dart';

enum PromptDeliveryState {
  created,
  waitingForInputSurface,
  staged,
  submitIssued,
  confirmed,
  submittedUnknown,
  failed,
}

extension PromptDeliveryStateX on PromptDeliveryState {
  bool get isTerminal =>
      this == PromptDeliveryState.confirmed ||
      this == PromptDeliveryState.submittedUnknown ||
      this == PromptDeliveryState.failed;

  bool get canIssueSubmit =>
      this == PromptDeliveryState.created ||
      this == PromptDeliveryState.waitingForInputSurface ||
      this == PromptDeliveryState.staged;
}

/// The durable intent to inject one user prompt into a runtime seat.
final class PromptDeliveryRequest {
  const PromptDeliveryRequest({
    required this.seat,
    required this.cli,
    required this.text,
    this.deliveryId,
  });

  final RuntimeSeatKey seat;
  final CliTool cli;
  final String text;

  /// Explicit delivery id for workflow-tracked sends (team-generation
  /// handoff). When provided, the coordinator returns the existing record
  /// only if seat/cli/text match exactly; otherwise creates with this ID.
  final String? deliveryId;
}

/// A durable snapshot of one prompt-delivery state machine.
final class PromptDelivery {
  const PromptDelivery({
    required this.id,
    required this.seat,
    required this.cli,
    required this.text,
    required this.normalizedText,
    required this.promptEpoch,
    required this.state,
    required this.createdAt,
    required this.updatedAt,
    this.acceptsWeakConfirmation = true,
    this.failureReason,
  });

  final String id;
  final RuntimeSeatKey seat;
  final CliTool cli;
  final String text;
  final String normalizedText;

  /// Increases for every delivery created for a seat. For adapters without a
  /// delivery id in their hook payload, only the currently active epoch may
  /// consume a same-text confirmation.
  final int promptEpoch;
  final PromptDeliveryState state;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// A weak text-only hook cannot safely distinguish a duplicate of an older
  /// identical prompt. Once a seat has weakly confirmed text, a later send of
  /// that exact normalized text requires exact correlation to become confirmed.
  final bool acceptsWeakConfirmation;
  final String? failureReason;

  PromptDelivery copyWith({
    PromptDeliveryState? state,
    DateTime? updatedAt,
    bool? acceptsWeakConfirmation,
    String? failureReason,
    bool clearFailureReason = false,
  }) => PromptDelivery(
    id: id,
    seat: seat,
    cli: cli,
    text: text,
    normalizedText: normalizedText,
    promptEpoch: promptEpoch,
    state: state ?? this.state,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    acceptsWeakConfirmation:
        acceptsWeakConfirmation ?? this.acceptsWeakConfirmation,
    failureReason: clearFailureReason
        ? null
        : failureReason ?? this.failureReason,
  );
}

/// Normalization used for hook correlation, while [PromptDelivery.text] keeps
/// the exact user-authored prompt for terminal injection and recovery UI.
String normalizePromptText(String text) =>
    text.trim().replaceAll(RegExp(r'\s+'), ' ');
