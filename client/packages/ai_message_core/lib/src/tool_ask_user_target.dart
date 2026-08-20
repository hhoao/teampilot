import 'message.dart';

/// One authored option for an [AiAskUserQuestion].
class AiAskUserOption {
  const AiAskUserOption({required this.label, this.description, this.id});

  final String label;
  final String? description;
  final String? id;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AiAskUserOption &&
          label == other.label &&
          description == other.description &&
          id == other.id;

  @override
  int get hashCode => Object.hash(label, description, id);
}

/// A single live ask-user question (options + optional multi-select).
class AiAskUserQuestion {
  const AiAskUserQuestion({
    required this.question,
    required this.options,
    this.multiSelect = false,
    this.header,
    this.id,
  });

  final String question;
  final List<AiAskUserOption> options;
  final bool multiSelect;
  final String? header;
  final String? id;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AiAskUserQuestion &&
          question == other.question &&
          _sameOptions(options, other.options) &&
          multiSelect == other.multiSelect &&
          header == other.header &&
          id == other.id;

  @override
  int get hashCode =>
      Object.hash(question, Object.hashAll(options), multiSelect, header, id);

  static bool _sameOptions(List<AiAskUserOption> a, List<AiAskUserOption> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// One question/answer pair for an ask-user history bubble.
class AiAskUserItem {
  const AiAskUserItem({required this.question, this.answer});

  final String question;

  /// Null when the user has not answered yet.
  final String? answer;
}

/// Parsed ask-user tool call ready for chat chrome.
class AiAskUserTarget {
  const AiAskUserTarget({required this.items, required this.asking});

  final List<AiAskUserItem> items;

  /// True while the tool call is still running / incomplete.
  final bool asking;
}

abstract class AiAskUserResolver {
  AiAskUserTarget? resolve(AiToolCallPart part);
}
