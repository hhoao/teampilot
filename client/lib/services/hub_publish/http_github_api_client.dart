import 'dart:convert';

import 'package:http/http.dart' as http;

import '../github/github_http.dart';
import 'github_registry_publisher.dart';

/// HTTP implementation of [GithubApiClient] against `api.github.com`.
class HttpGithubApiClient implements GithubApiClient {
  HttpGithubApiClient({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  static final _apiBase = Uri.parse('https://api.github.com');

  Map<String, String> _headers(String token) => githubApiHeaders(token: token);

  Uri _uri(String path, [Map<String, String>? query]) =>
      _apiBase.replace(path: path, queryParameters: query);

  @override
  Future<GithubRepoInfo> getRepo({
    required String owner,
    required String name,
    required String token,
  }) async {
    final res = await _client.get(
      _uri('/repos/$owner/$name'),
      headers: _headers(token),
    );
    _ensureOk(res, 'getRepo');
    final json = (jsonDecode(res.body) as Map).cast<String, Object?>();
    return GithubRepoInfo(
      owner: owner,
      name: name,
      defaultBranch: json['default_branch'] as String? ?? 'main',
    );
  }

  @override
  Future<String> getDefaultBranchSha({
    required String owner,
    required String name,
    required String branch,
    required String token,
  }) async {
    final res = await _client.get(
      _uri('/repos/$owner/$name/git/ref/heads/$branch'),
      headers: _headers(token),
    );
    _ensureOk(res, 'getDefaultBranchSha');
    final json = (jsonDecode(res.body) as Map).cast<String, Object?>();
    final object = (json['object'] as Map?)?.cast<String, Object?>();
    final sha = object?['sha'] as String?;
    if (sha == null || sha.isEmpty) {
      throw HubPublishException(
        HubPublishErrorCode.apiError,
        'Missing SHA for $owner/$name@$branch',
      );
    }
    return sha;
  }

  @override
  Future<GithubFileContent?> getFileContent({
    required String owner,
    required String name,
    required String path,
    String? ref,
    required String token,
  }) async {
    final res = await _client.get(
      _uri(
        '/repos/$owner/$name/contents/$path',
        ref == null ? null : {'ref': ref},
      ),
      headers: _headers(token),
    );
    if (res.statusCode == 404) return null;
    _ensureOk(res, 'getFileContent');
    final json = (jsonDecode(res.body) as Map).cast<String, Object?>();
    final encoding = json['encoding'] as String? ?? '';
    final raw = json['content'] as String? ?? '';
    final content = encoding == 'base64'
        ? utf8.decode(base64.decode(raw.replaceAll('\n', '')))
        : raw;
    return GithubFileContent(
      path: path,
      content: content,
      sha: json['sha'] as String? ?? '',
    );
  }

  @override
  Future<GithubUser> getAuthenticatedUser({required String token}) async {
    final res = await _client.get(
      _uri('/user'),
      headers: _headers(token),
    );
    _ensureOk(res, 'getAuthenticatedUser');
    final json = (jsonDecode(res.body) as Map).cast<String, Object?>();
    final login = json['login'] as String? ?? '';
    if (login.isEmpty) {
      throw const HubPublishException(
        HubPublishErrorCode.apiError,
        'Authenticated user login missing',
      );
    }
    return GithubUser(login: login);
  }

  @override
  Future<GithubForkInfo> ensureFork({
    required String upstreamOwner,
    required String upstreamName,
    required String token,
  }) async {
    final user = await getAuthenticatedUser(token: token);
    final existing = await _client.get(
      _uri('/repos/${user.login}/$upstreamName'),
      headers: _headers(token),
    );
    if (existing.statusCode == 200) {
      final json = (jsonDecode(existing.body) as Map).cast<String, Object?>();
      final parent = (json['parent'] as Map?)?.cast<String, Object?>();
      final parentFull = parent?['full_name'] as String?;
      if (parentFull == '$upstreamOwner/$upstreamName' ||
          json['fork'] == true) {
        return GithubForkInfo(owner: user.login, name: upstreamName);
      }
    }

    final res = await _client.post(
      _uri('/repos/$upstreamOwner/$upstreamName/forks'),
      headers: {
        ..._headers(token),
        'Content-Type': 'application/json',
      },
      body: '{}',
    );
    if (res.statusCode != 202 && res.statusCode != 201 && res.statusCode != 200) {
      throw HubPublishException(
        HubPublishErrorCode.apiError,
        githubApiErrorMessage(res.statusCode, responseHeaders: res.headers),
      );
    }
    final json = (jsonDecode(res.body) as Map).cast<String, Object?>();
    final fullName =
        json['full_name'] as String? ?? '${user.login}/$upstreamName';
    final parts = fullName.split('/');
    return GithubForkInfo(
      owner: parts.isNotEmpty ? parts.first : user.login,
      name: parts.length > 1 ? parts[1] : upstreamName,
    );
  }

  @override
  Future<void> createBranch({
    required String owner,
    required String name,
    required String branch,
    required String fromSha,
    required String token,
  }) async {
    final res = await _client.post(
      _uri('/repos/$owner/$name/git/refs'),
      headers: {
        ..._headers(token),
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'ref': 'refs/heads/$branch',
        'sha': fromSha,
      }),
    );
    if (res.statusCode == 422) {
      // Branch may already exist from a prior attempt; allow reuse.
      return;
    }
    _ensureOk(res, 'createBranch');
  }

  @override
  Future<void> putFile({
    required String owner,
    required String name,
    required String path,
    required String branch,
    required String content,
    required String message,
    String? sha,
    required String token,
  }) async {
    final body = <String, Object?>{
      'message': message,
      'content': base64.encode(utf8.encode(content)),
      'branch': branch,
      if (sha != null && sha.isNotEmpty) 'sha': sha,
    };
    final res = await _client.put(
      _uri('/repos/$owner/$name/contents/$path'),
      headers: {
        ..._headers(token),
        'Content-Type': 'application/json',
      },
      body: jsonEncode(body),
    );
    _ensureOk(res, 'putFile');
  }

  @override
  Future<GithubPullRequest> openPullRequest({
    required String owner,
    required String name,
    required String title,
    required String head,
    required String base,
    String? body,
    required String token,
  }) async {
    final res = await _client.post(
      _uri('/repos/$owner/$name/pulls'),
      headers: {
        ..._headers(token),
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'title': title,
        'head': head,
        'base': base,
        if (body != null) 'body': body,
      }),
    );
    _ensureOk(res, 'openPullRequest');
    final json = (jsonDecode(res.body) as Map).cast<String, Object?>();
    final htmlUrl = json['html_url'] as String? ?? '';
    final number = (json['number'] as num?)?.toInt() ?? 0;
    if (htmlUrl.isEmpty) {
      throw const HubPublishException(
        HubPublishErrorCode.apiError,
        'Pull request response missing html_url',
      );
    }
    return GithubPullRequest(htmlUrl: htmlUrl, number: number);
  }

  void _ensureOk(http.Response res, String op) {
    if (res.statusCode >= 200 && res.statusCode < 300) return;
    throw HubPublishException(
      HubPublishErrorCode.apiError,
      '$op failed: ${githubApiErrorMessage(res.statusCode, responseHeaders: res.headers)}',
    );
  }
}
