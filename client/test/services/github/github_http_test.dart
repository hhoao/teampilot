import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/github/github_http.dart';

void main() {
  group('githubApiHeaders', () {
    test('includes REST accept and API version', () {
      final headers = githubApiHeaders(userAgent: 'test-agent');
      expect(headers['Accept'], 'application/vnd.github+json');
      expect(headers['X-GitHub-Api-Version'], '2022-11-28');
      expect(headers['User-Agent'], 'test-agent');
    });
  });

  group('githubApiErrorMessage', () {
    test('mentions rate limit reset when remaining is zero', () {
      final message = githubApiErrorMessage(
        403,
        responseHeaders: {
          'x-ratelimit-remaining': '0',
          'x-ratelimit-reset': '1700000000',
        },
      );
      expect(message, contains('rate limit'));
      expect(message, contains('GITHUB_TOKEN'));
    });

    test('generic message for other status codes', () {
      expect(
        githubApiErrorMessage(500),
        'GitHub API returned 500. Try again later.',
      );
    });
  });
}
