import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/ai/commit_message_prompt.dart';

void main() {
  test('prompt includes the diff and Conventional Commits guidance', () {
    final prompt = buildCommitMessagePrompt('diff --git a/x b/x');
    expect(prompt, contains('diff --git a/x b/x'));
    expect(prompt, contains('Conventional Commits'));
    expect(prompt.toLowerCase(), contains('english'));
  });

  test('cleaner strips code fences and surrounding whitespace', () {
    const raw = '```\nfeat: add thing\n\nbody line\n```\n';
    expect(cleanCommitMessageOutput(raw), 'feat: add thing\n\nbody line');
  });

  test('cleaner strips a leading language fence tag', () {
    const raw = '```text\nfix: bug\n```';
    expect(cleanCommitMessageOutput(raw), 'fix: bug');
  });

  test('cleaner passes through plain text unchanged', () {
    expect(cleanCommitMessageOutput('  feat: x  '), 'feat: x');
  });
}
