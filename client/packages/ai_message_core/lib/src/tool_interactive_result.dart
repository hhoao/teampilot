/// Result of an in-chat interactive action (ask-user submit, plan approve, …).
sealed class AiInteractiveResult {
  const AiInteractiveResult();
}

final class AiInteractiveOk extends AiInteractiveResult {
  const AiInteractiveOk();
}

final class AiInteractiveFailed extends AiInteractiveResult {
  const AiInteractiveFailed(this.reason);

  /// Host-specific reason code (e.g. `terminal_disconnected`).
  final String reason;
}

/// Answers collected by the ask-user card, ready for the host to deliver.
class AiAskUserSubmission {
  const AiAskUserSubmission({
    required this.answers,
    required this.optionIndices,
    this.freeText,
    this.freeTexts,
  });

  final List<List<String>> answers;
  final List<int> optionIndices;
  final String? freeText;
  final List<String?>? freeTexts;
}
