import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import 'download_candidate.dart';
import 'remote_download_http.dart';
import 'remote_download_resolver.dart';

class RemoteDownloadCancelledException implements Exception {
  RemoteDownloadCancelledException(this.message);

  final String message;

  @override
  String toString() => message;
}

class RemoteDownloader {
  RemoteDownloader({
    required http.Client client,
    required RemoteDownloadResolver resolver,
  })  : _client = client,
        _resolver = resolver;

  final http.Client _client;
  final RemoteDownloadResolver _resolver;

  Future<File> fetch(
    Uri logical, {
    required String destFileName,
    Directory? tempRoot,
    Map<String, String>? headers,
    String? expectedSha256,
    void Function(int received, int? total)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final candidates = _resolver.resolve(logical);
    final attempts = <RemoteDownloadAttempt>[];

    for (final candidate in candidates) {
      try {
        return await _fetchCandidate(
          candidate,
          destFileName: destFileName,
          tempRoot: tempRoot,
          headers: headers,
          expectedSha256: expectedSha256,
          onProgress: onProgress,
          isCancelled: isCancelled,
        );
      } on RemoteDownloadCancelledException {
        rethrow;
      } on _CandidateChecksumMismatch catch (error) {
        attempts.add(error.attempt);
      } catch (error) {
        attempts.add(
          RemoteDownloadAttempt(
            uri: candidate.uri,
            sourceId: candidate.sourceId,
            statusCode: error is _CandidateHttpFailure ? error.statusCode : null,
            error: error is _CandidateHttpFailure ? null : error,
          ),
        );
      }
    }

    throw RemoteDownloadException(
      RemoteDownloadHttp.failureMessage(attempts),
      attempts: attempts,
    );
  }

  Future<File> _fetchCandidate(
    DownloadCandidate candidate, {
    required String destFileName,
    Directory? tempRoot,
    Map<String, String>? headers,
    String? expectedSha256,
    void Function(int received, int? total)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final root = tempRoot ?? Directory.systemTemp;
    final downloadDir = await root.createTemp('teampilot_download_');
    final partialFile = File(p.join(downloadDir.path, '.partial'));
    final destFile = File(p.join(downloadDir.path, destFileName));

    final request = http.Request('GET', candidate.uri);
    if (headers != null) {
      request.headers.addAll(headers);
    }

    try {
      final streamed = await _client.send(request);
      if (streamed.statusCode != 200) {
        throw _CandidateHttpFailure(streamed.statusCode);
      }

      final total = _contentLength(streamed);
      final sink = partialFile.openWrite();
      var received = 0;

      try {
        await for (final chunk in streamed.stream) {
          if (isCancelled?.call() == true) {
            throw RemoteDownloadCancelledException('Download cancelled');
          }
          sink.add(chunk);
          received += chunk.length;
          onProgress?.call(received, total);
        }
      } finally {
        await sink.close();
      }

      if (expectedSha256 != null) {
        final bytes = await partialFile.readAsBytes();
        final hash = sha256.convert(bytes).toString();
        if (hash != expectedSha256.toLowerCase()) {
          throw _CandidateChecksumMismatch(
            RemoteDownloadAttempt(
              uri: candidate.uri,
              sourceId: candidate.sourceId,
              error: 'sha256 mismatch',
            ),
          );
        }
      }

      await partialFile.rename(destFile.path);
      return destFile;
    } catch (error) {
      if (downloadDir.existsSync()) {
        await downloadDir.delete(recursive: true);
      }
      rethrow;
    }
  }

  static int? _contentLength(http.StreamedResponse response) {
    final contentLength = response.contentLength;
    if (contentLength != null && contentLength > 0) {
      return contentLength;
    }
    final header = response.headers['content-length'];
    if (header == null) {
      return null;
    }
    return int.tryParse(header);
  }
}

class _CandidateHttpFailure implements Exception {
  _CandidateHttpFailure(this.statusCode);

  final int statusCode;
}

class _CandidateChecksumMismatch implements Exception {
  _CandidateChecksumMismatch(this.attempt);

  final RemoteDownloadAttempt attempt;
}
