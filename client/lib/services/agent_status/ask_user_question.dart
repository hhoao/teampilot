/// One authored option for an [AgentAskUserQuestion] (from the CLI model).
class AgentAskUserOption {
  const AgentAskUserOption({required this.label, this.description});

  final String label;
  final String? description;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AgentAskUserOption &&
          label == other.label &&
          description == other.description;

  @override
  int get hashCode => Object.hash(label, description);
}

/// A single AskUserQuestion item from a Claude-family `PreToolUse` hook
/// payload (`tool_input`), surfaced so the chat can render and answer it.
class AgentAskUserQuestion {
  const AgentAskUserQuestion({
    required this.question,
    required this.options,
    this.multiSelect = false,
    this.header,
  });

  final String question;
  final List<AgentAskUserOption> options;

  /// True for checkbox-style selection; single-select (radio) when false.
  final bool multiSelect;

  /// Short tab label when multiple questions are shown (Claude `header`).
  final String? header;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AgentAskUserQuestion &&
          question == other.question &&
          _sameOptions(options, other.options) &&
          multiSelect == other.multiSelect &&
          header == other.header;

  @override
  int get hashCode =>
      Object.hash(question, Object.hashAll(options), multiSelect, header);

  static bool _sameOptions(
    List<AgentAskUserOption> a,
    List<AgentAskUserOption> b,
  ) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Parses the `tool_input` of an AskUserQuestion `PreToolUse` hook payload into
/// structured questions.
///
/// Lenient by design — the CLI schema can drift (`options` may be strings or
/// objects, multi-select flags differ per CLI): malformed entries are skipped
/// and a payload with no valid question yields null.
List<AgentAskUserQuestion>? parseAskUserQuestions(Object? toolInput) {
  if (toolInput is! Map) return null;
  return parseQuestionsList(toolInput['questions']);
}

/// Parses a raw `questions` array directly.
///
/// opencode's `question.asked` status POST carries the array at the top level
/// (not under `tool_input`), with `multiple` as the multi-select flag and
/// `{label, explanation}` options — both accepted alongside the Claude-family
/// variants here.
List<AgentAskUserQuestion>? parseQuestionsList(Object? rawQuestions) {
  if (rawQuestions is! List || rawQuestions.isEmpty) return null;

  final result = <AgentAskUserQuestion>[];
  for (final raw in rawQuestions) {
    if (raw is! Map) continue;
    final questionText = raw['question'];
    if (questionText is! String || questionText.trim().isEmpty) continue;
    final options = _parseOptions(raw['options']);
    if (options.isEmpty) continue;
    final headerRaw = raw['header'];
    final header = headerRaw is String && headerRaw.trim().isNotEmpty
        ? headerRaw.trim()
        : null;
    result.add(
      AgentAskUserQuestion(
        question: questionText.trim(),
        options: options,
        multiSelect: raw['multiSelect'] == true ||
            raw['multi_select'] == true ||
            raw['multiple'] == true,
        header: header,
      ),
    );
  }
  return result.isEmpty ? null : result;
}

List<AgentAskUserOption> _parseOptions(Object? raw) {
  if (raw is! List) return const [];
  final options = <AgentAskUserOption>[];
  for (final o in raw) {
    if (o is String && o.trim().isNotEmpty) {
      options.add(AgentAskUserOption(label: o.trim()));
    } else if (o is Map) {
      final label = o['label'];
      if (label is! String || label.trim().isEmpty) continue;
      final description = o['description'] ?? o['explanation'];
      options.add(
        AgentAskUserOption(
          label: label.trim(),
          description: description is String && description.trim().isNotEmpty
              ? description.trim()
              : null,
        ),
      );
    }
  }
  return options;
}
