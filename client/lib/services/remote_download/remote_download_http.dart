import 'package:http/http.dart' as http;

import 'remote_download_resolver.dart';

class RemoteDownloadAttempt {
  const RemoteDownloadAttempt({
    required this.uri,
    required this.sourceId,
    this.statusCode,
    this.error,
  });

  final Uri uri;
  final String sourceId;
  final int? statusCode;
  final Object? error;
}

class RemoteDownloadException implements Exception {
  RemoteDownloadException(this.message, {this.attempts = const []});

  final String message;
  final List<RemoteDownloadAttempt> attempts;

  @override
  String toString() => message;
}

class RemoteDownloadHttp {
  RemoteDownloadHttp({
    required http.Client client,
    required RemoteDownloadResolver resolver,
  })  : _client = client,
        _resolver = resolver;

  final http.Client _client;
  final RemoteDownloadResolver _resolver;

  Future<http.Response> get(
    Uri logical, {
    Map<String, String>? headers,
  }) {
    return _tryResponseCandidates(
      logical,
      (uri) => _client.get(uri, headers: headers),
    );
  }

  Future<http.Response> head(
    Uri logical, {
    Map<String, String>? headers,
  }) {
    return _tryResponseCandidates(
      logical,
      (uri) => _client.head(uri, headers: headers),
    );
  }

  Future<http.StreamedResponse> send(
    http.BaseRequest Function(Uri candidateUri) buildRequest,
    Uri logical,
  ) async {
    final candidates = _resolver.resolve(logical);
    final attempts = <RemoteDownloadAttempt>[];

    for (final candidate in candidates) {
      try {
        final request = buildRequest(candidate.uri);
        return await _client.send(request);
      } catch (error) {
        attempts.add(
          RemoteDownloadAttempt(
            uri: candidate.uri,
            sourceId: candidate.sourceId,
            error: error,
          ),
        );
      }
    }

    throw RemoteDownloadException(
      failureMessage(attempts),
      attempts: attempts,
    );
  }

  Future<http.Response> _tryResponseCandidates(
    Uri logical,
    Future<http.Response> Function(Uri uri) request,
  ) async {
    final candidates = _resolver.resolve(logical);
    final attempts = <RemoteDownloadAttempt>[];

    for (final candidate in candidates) {
      try {
        final response = await request(candidate.uri);
        if (_isSuccessStatus(response.statusCode)) {
          return response;
        }
        attempts.add(
          RemoteDownloadAttempt(
            uri: candidate.uri,
            sourceId: candidate.sourceId,
            statusCode: response.statusCode,
          ),
        );
      } catch (error) {
        attempts.add(
          RemoteDownloadAttempt(
            uri: candidate.uri,
            sourceId: candidate.sourceId,
            error: error,
          ),
        );
      }
    }

    throw RemoteDownloadException(
      failureMessage(attempts),
      attempts: attempts,
    );
  }

  static bool _isSuccessStatus(int statusCode) =>
      statusCode >= 200 && statusCode < 300;

  static String failureMessage(List<RemoteDownloadAttempt> attempts) {
    final details = attempts
        .map((attempt) {
          final status = attempt.statusCode;
          if (status != null) {
            return '${attempt.sourceId}@${attempt.uri} -> $status';
          }
          return '${attempt.sourceId}@${attempt.uri} -> ${attempt.error}';
        })
        .join('; ');
    return 'All download candidates failed: $details';
  }
}
