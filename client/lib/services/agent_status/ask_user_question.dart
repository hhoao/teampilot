import 'dart:convert';

/// One authored option for an [AgentAskUserQuestion] (from the CLI model).
class AgentAskUserOption {
  const AgentAskUserOption({required this.label, this.description, this.id});

  final String label;
  final String? description;

  /// Cursor `AskQuestion` option id; used to map selected ids back to labels.
  final String? id;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AgentAskUserOption &&
          label == other.label &&
          description == other.description &&
          id == other.id;

  @override
  int get hashCode => Object.hash(label, description, id);
}

/// A single AskUserQuestion item from a Claude-family `PreToolUse` hook
/// payload (`tool_input`), surfaced so the chat can render and answer it.
class AgentAskUserQuestion {
  const AgentAskUserQuestion({
    required this.question,
    required this.options,
    this.multiSelect = false,
    this.header,
    this.id,
  });

  final String question;
  final List<AgentAskUserOption> options;

  /// True for checkbox-style selection; single-select (radio) when false.
  final bool multiSelect;

  /// Short tab label when multiple questions are shown (Claude `header`).
  final String? header;

  /// Cursor `AskQuestion` question id; used to map answers keyed by id.
  final String? id;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AgentAskUserQuestion &&
          question == other.question &&
          _sameOptions(options, other.options) &&
          multiSelect == other.multiSelect &&
          header == other.header &&
          id == other.id;

  @override
  int get hashCode =>
      Object.hash(question, Object.hashAll(options), multiSelect, header, id);

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
/// variants here. Cursor `AskQuestion` uses `prompt` / `title` / `allow_multiple`.
List<AgentAskUserQuestion>? parseQuestionsList(Object? rawQuestions) {
  if (rawQuestions is! List || rawQuestions.isEmpty) return null;

  final result = <AgentAskUserQuestion>[];
  for (final raw in rawQuestions) {
    if (raw is! Map) continue;
    final questionText = _firstNonEmptyString(raw, const [
      'question',
      'prompt',
      'title',
    ]);
    if (questionText == null) continue;
    final options = _parseOptions(raw['options']);
    if (options.isEmpty) continue;
    final headerRaw = raw['header'];
    final header = headerRaw is String && headerRaw.trim().isNotEmpty
        ? headerRaw.trim()
        : null;
    result.add(
      AgentAskUserQuestion(
        question: questionText,
        options: options,
        multiSelect:
            raw['multiSelect'] == true ||
            raw['multi_select'] == true ||
            raw['multiple'] == true ||
            raw['allow_multiple'] == true,
        header: header,
        id: _nonEmptyString(raw['id']),
      ),
    );
  }
  return result.isEmpty ? null : result;
}

/// Display labels for each question, aligned with [questions].
///
/// A null slot means that question has no parsed answer yet. Multi-select
/// labels are joined with `', '`.
List<String?> parseAskUserAnswers({
  required List<AgentAskUserQuestion> questions,
  required Object? result,
}) {
  if (questions.isEmpty) return const [];
  final payload = _answersPayload(result);
  return [
    for (var i = 0; i < questions.length; i++)
      _formatAnswer(
        question: questions[i],
        index: i,
        payload: payload,
        rawResult: result,
      ),
  ];
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
          id: _nonEmptyString(o['id']),
        ),
      );
    }
  }
  return options;
}

String? _firstNonEmptyString(Map raw, List<String> keys) {
  for (final key in keys) {
    final value = _nonEmptyString(raw[key]);
    if (value != null) return value;
  }
  return null;
}

String? _nonEmptyString(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

Object? _decodeResult(Object? result) {
  if (result is! String) return result;
  final trimmed = result.trim();
  if (trimmed.isEmpty) return null;
  try {
    return jsonDecode(trimmed);
  } on Object {
    return trimmed;
  }
}

/// Normalized answers payload: a Map, a List, or a raw String.
Object? _answersPayload(Object? result) {
  final decoded = _decodeResult(result);
  if (decoded is Map && decoded.containsKey('answers')) {
    return decoded['answers'];
  }
  return decoded;
}

String? _formatAnswer({
  required AgentAskUserQuestion question,
  required int index,
  required Object? payload,
  required Object? rawResult,
}) {
  final tokens = _tokensForQuestion(
    question: question,
    index: index,
    payload: payload,
    rawResult: rawResult,
  );
  if (tokens.isEmpty) return null;
  final labels = [for (final token in tokens) _labelForToken(question, token)];
  return labels.join(', ');
}

List<String> _tokensForQuestion({
  required AgentAskUserQuestion question,
  required int index,
  required Object? payload,
  required Object? rawResult,
}) {
  if (payload is Map) {
    final byText = payload[question.question];
    if (byText != null) return _tokensFrom(byText);
    final id = question.id;
    if (id != null) {
      final byId = payload[id];
      if (byId != null) return _tokensFrom(byId);
    }
    return const [];
  }
  if (payload is List) {
    if (index < payload.length) {
      return _tokensFrom(payload[index]);
    }
    for (final item in payload) {
      if (item is! Map) continue;
      final itemId = _nonEmptyString(item['id']);
      if (itemId != null && itemId == question.id) {
        return _tokensFrom(item);
      }
    }
    return const [];
  }
  if (payload is String && index == 0) {
    return [payload];
  }
  // Last resort: a non-JSON string result answers only the first question.
  if (index == 0 && rawResult is String) {
    final trimmed = rawResult.trim();
    return trimmed.isEmpty ? const [] : [trimmed];
  }
  return const [];
}

List<String> _tokensFrom(Object? value) {
  if (value == null) return const [];
  if (value is String) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? const [] : [trimmed];
  }
  if (value is List) {
    return [for (final item in value) ..._tokensFrom(item)];
  }
  if (value is Map) {
    for (final key in const [
      'selected',
      'selectedOptions',
      'answers',
      'labels',
      'answer',
    ]) {
      if (value.containsKey(key)) return _tokensFrom(value[key]);
    }
  }
  return const [];
}

String _labelForToken(AgentAskUserQuestion question, String token) {
  for (final option in question.options) {
    if (option.label == token) return option.label;
  }
  for (final option in question.options) {
    if (option.id == token) return option.label;
  }
  return token;
}

/// True for AskUserQuestion across casing variants (`AskUserQuestion`,
/// `ask_user_question`, `askUserQuestion`) — same rule as Orca.
bool isAskUserQuestionTool(String? toolName) {
  if (toolName == null || toolName.isEmpty) return false;
  final compact = toolName
      .replaceAll(RegExp(r'[^a-zA-Z0-9]'), '')
      .toLowerCase();
  return compact == 'askuserquestion';
}
