import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:teampilot/services/hub_publish/github_registry_publisher.dart';
import 'package:teampilot/services/hub_publish/http_github_api_client.dart';

void main() {
  group('HttpGithubApiClient', () {
    test('getRepo maps 401 to unauthorized', () async {
      final client = HttpGithubApiClient(
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({'message': 'Bad credentials'}),
            401,
          ),
        ),
      );

      await expectLater(
        client.getRepo(owner: 'hhoao', name: 'teampilot', token: 'bad'),
        throwsA(
          isA<HubPublishException>().having(
            (e) => e.code,
            'code',
            HubPublishErrorCode.unauthorized,
          ),
        ),
      );
    });

    test('ensureFork maps fork POST 401 to unauthorized', () async {
      final client = HttpGithubApiClient(
        client: MockClient((request) async {
          final path = request.url.path;
          if (path == '/user') {
            return http.Response(jsonEncode({'login': 'alice'}), 200);
          }
          if (path == '/repos/alice/teampilot') {
            return http.Response('Not Found', 404);
          }
          if (path == '/repos/hhoao/teampilot/forks') {
            return http.Response(
              jsonEncode({'message': 'Bad credentials'}),
              401,
            );
          }
          return http.Response('unexpected', 500);
        }),
      );

      await expectLater(
        client.ensureFork(
          upstreamOwner: 'hhoao',
          upstreamName: 'teampilot',
          token: 'bad',
        ),
        throwsA(
          isA<HubPublishException>().having(
            (e) => e.code,
            'code',
            HubPublishErrorCode.unauthorized,
          ),
        ),
      );
    });
  });
}
