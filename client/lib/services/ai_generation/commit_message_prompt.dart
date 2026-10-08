/// Builds the prompt for generating a commit message from a staged diff.
///
/// The diff is interpolated unescaped. This is deliberate and safe here: it is a
/// local-only desktop feature, the user authored the diff, and the generated
/// message is always shown for review/edit before committing — no privilege
/// boundary is crossed by adversarial diff text.
String buildCommitMessagePrompt(String stagedDiff) {
  return '''
You are a tool that writes a single git commit message for the staged changes.

Rules:
- Use the Conventional Commits format: type(scope): subject
- Subject in the imperative mood, no trailing period, <= 72 characters.
- If helpful, add a blank line then a short body with "- " bullet points.
- Write the message in English.
- Output ONLY the commit message. No explanations, no code fences, no quotes.

Staged diff:
$stagedDiff
''';
}

/// Cleans model output into a bare commit message: trims whitespace and strips
/// a surrounding triple-backtick code fence (with optional language tag).
String cleanCommitMessageOutput(String raw) {
  var text = raw.trim();
  if (text.startsWith('```')) {
    final firstNewline = text.indexOf('\n');
    if (firstNewline != -1) {
      text = text.substring(firstNewline + 1);
    } else {
      text = text.substring(3);
    }
    final fenceEnd = text.lastIndexOf('```');
    if (fenceEnd != -1) {
      text = text.substring(0, fenceEnd);
    }
  }
  return text.trim();
}
