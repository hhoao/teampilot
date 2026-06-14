import 'dart:io';

/// GitHub rejects REST and raw requests without a recognizable User-Agent.
const kGithubHttpUserAgent =
    'teampilot/1.0 (https://github.com/hhoao/teampilot)';

/// Reads [GITHUB_TOKEN] or [GH_TOKEN] when the host exposes environment vars.
String? readGithubTokenFromEnvironment() {
  try {
    final token =
        Platform.environment['GITHUB_TOKEN'] ??
        Platform.environment['GH_TOKEN'];
    final trimmed = token?.trim();
    if (trimmed != null && trimmed.isNotEmpty) return trimmed;
  } catch (_) {}
  return null;
}

/// Headers for `api.github.com` REST calls (releases, commits, …).
Map<String, String> githubApiHeaders({
  String userAgent = kGithubHttpUserAgent,
  String? token,
}) {
  final headers = <String, String>{
    'Accept': 'application/vnd.github+json',
    'X-GitHub-Api-Version': '2022-11-28',
    'User-Agent': userAgent,
  };
  final auth = token ?? readGithubTokenFromEnvironment();
  if (auth != null) {
    headers['Authorization'] = 'Bearer $auth';
  }
  return headers;
}

/// Headers for `github.com` pages and `releases/download` assets.
Map<String, String> githubHttpHeaders({
  String userAgent = kGithubHttpUserAgent,
}) => {'User-Agent': userAgent};

bool githubApiStatusIsRateLimited(int statusCode) =>
    statusCode == 403 || statusCode == 429;

/// User-facing message for failed GitHub API responses.
String githubApiErrorMessage(
  int statusCode, {
  Map<String, String>? responseHeaders,
}) {
  if (githubApiStatusIsRateLimited(statusCode)) {
    final remaining = responseHeaders?['x-ratelimit-remaining'];
    if (remaining == '0') {
      final resetEpoch = int.tryParse(
        responseHeaders?['x-ratelimit-reset'] ?? '',
      );
      if (resetEpoch != null) {
        final resetAt = DateTime.fromMillisecondsSinceEpoch(
          resetEpoch * 1000,
          isUtc: true,
        ).toLocal();
        return 'GitHub API rate limit exceeded. Try again after '
            '${resetAt.hour.toString().padLeft(2, '0')}:'
            '${resetAt.minute.toString().padLeft(2, '0')}, or set '
            'GITHUB_TOKEN for a higher limit.';
      }
      return 'GitHub API rate limit exceeded. Try again later, or set '
          'GITHUB_TOKEN for a higher limit.';
    }
    return 'GitHub API access denied ($statusCode). Try again later, or set '
        'GITHUB_TOKEN if you use the API frequently.';
  }
  return 'GitHub API returned $statusCode. Try again later.';
}
