import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/expert_hub/expert_hub_source.dart';
import 'package:teampilot/services/hub_publish/github_registry_publisher.dart';
import 'package:teampilot/services/team_hub/team_hub_source.dart';

class FakeGithubApi implements GithubApiClient {
  FakeGithubApi({
    this.upstreamIndexJson = '{"members":[]}',
    this.defaultBranch = 'main',
    this.defaultSha = 'abc123',
    this.forkOwner = 'alice',
    this.authenticatedLogin = 'alice',
    this.prHtmlUrl = 'https://github.com/hhoao/teampilot/pull/1',
  });

  String upstreamIndexJson;
  String defaultBranch;
  String defaultSha;
  String forkOwner;
  String authenticatedLogin;
  String prHtmlUrl;

  var ensuredFork = false;
  var updatedIndex = false;
  var openedPr = false;
  final writtenPaths = <String>[];
  final createdBranches = <String>[];
  String? lastPrHead;
  String? lastPrBase;

  @override
  Future<GithubRepoInfo> getRepo({
    required String owner,
    required String name,
    required String token,
  }) async {
    return GithubRepoInfo(
      owner: owner,
      name: name,
      defaultBranch: defaultBranch,
    );
  }

  @override
  Future<String> getDefaultBranchSha({
    required String owner,
    required String name,
    required String branch,
    required String token,
  }) async {
    return defaultSha;
  }

  @override
  Future<GithubFileContent?> getFileContent({
    required String owner,
    required String name,
    required String path,
    String? ref,
    required String token,
  }) async {
    if (path.endsWith('index.json')) {
      return GithubFileContent(
        path: path,
        content: upstreamIndexJson,
        sha: 'index-sha',
      );
    }
    return null;
  }

  @override
  Future<GithubUser> getAuthenticatedUser({required String token}) async {
    return GithubUser(login: authenticatedLogin);
  }

  @override
  Future<GithubForkInfo> ensureFork({
    required String upstreamOwner,
    required String upstreamName,
    required String token,
  }) async {
    ensuredFork = true;
    return GithubForkInfo(owner: forkOwner, name: upstreamName);
  }

  @override
  Future<void> createBranch({
    required String owner,
    required String name,
    required String branch,
    required String fromSha,
    required String token,
  }) async {
    createdBranches.add('$owner/$name:$branch@$fromSha');
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
    writtenPaths.add(path);
    if (path.endsWith('index.json')) {
      updatedIndex = true;
      upstreamIndexJson = content;
    }
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
    openedPr = true;
    lastPrHead = head;
    lastPrBase = base;
    return GithubPullRequest(htmlUrl: prHtmlUrl, number: 1);
  }
}

void main() {
  group('GithubRegistryPublisher', () {
    test('publish expert forks, commits member.json + index, opens PR', () async {
      final api = FakeGithubApi(
        upstreamIndexJson: '{"members":["other"]}',
      );
      final publisher = GithubRegistryPublisher(api: api);

      final result = await publisher.publishExpert(
        upstream: kDefaultExpertHubRegistry,
        slug: 'arch',
        memberJson: {
          'key': 'hhoao/teampilot/member-hub/arch',
          'name': 'Arch',
          'description': 'Architect',
          'category': 'Engineering',
          'member': {'name': 'Arch', 'prompt': 'design'},
        },
        token: 't',
      );

      expect(result.prUrl, isNotEmpty);
      expect(result.prUrl, api.prHtmlUrl);
      expect(result.registryFullName, kDefaultExpertHubRegistry.catalogPrefix);
      expect(api.ensuredFork, isTrue);
      expect(api.writtenPaths, contains('member-hub/members/arch/member.json'));
      expect(api.writtenPaths, contains('member-hub/index.json'));
      expect(api.updatedIndex, isTrue);
      expect(api.openedPr, isTrue);
      expect(api.lastPrHead, 'alice:publish-expert-arch');
      expect(api.lastPrBase, 'main');
      expect(api.createdBranches.single, contains('alice/teampilot:'));
    });

    test('slug collision on upstream index fails before write', () async {
      final api = FakeGithubApi(
        upstreamIndexJson: '{"members":["arch","other"]}',
      );
      final publisher = GithubRegistryPublisher(api: api);

      await expectLater(
        publisher.publishExpert(
          upstream: kDefaultExpertHubRegistry,
          slug: 'arch',
          memberJson: {
            'key': 'hhoao/teampilot/member-hub/arch',
            'name': 'Arch',
            'description': '',
            'category': '',
            'member': {'name': 'Arch', 'prompt': ''},
          },
          token: 't',
        ),
        throwsA(
          isA<HubPublishException>().having(
            (e) => e.code,
            'code',
            HubPublishErrorCode.slugCollision,
          ),
        ),
      );

      expect(api.ensuredFork, isFalse);
      expect(api.writtenPaths, isEmpty);
      expect(api.openedPr, isFalse);
    });

    test('publish team writes teams/<slug>/team.json and updates index', () async {
      final api = FakeGithubApi(
        upstreamIndexJson: '{"teams":[{"slug":"existing"}]}',
        prHtmlUrl: 'https://github.com/hhoao/teampilot/pull/2',
      );
      final publisher = GithubRegistryPublisher(api: api);

      final result = await publisher.publishTeam(
        upstream: kDefaultTeamHubRegistry,
        slug: 'platform',
        teamJson: {
          'key': 'hhoao/teampilot/team-hub/platform',
          'name': 'Platform',
          'description': 'Platform team',
          'category': 'Engineering',
          'updatedAt': 1,
          'roster': <Object?>[],
        },
        token: 't',
      );

      expect(result.prUrl, api.prHtmlUrl);
      expect(result.registryFullName, kDefaultTeamHubRegistry.catalogPrefix);
      expect(api.ensuredFork, isTrue);
      expect(api.writtenPaths, contains('team-hub/teams/platform/team.json'));
      expect(api.writtenPaths, contains('team-hub/index.json'));
      expect(api.updatedIndex, isTrue);
      expect(api.openedPr, isTrue);
      expect(api.lastPrHead, 'alice:publish-team-platform');
      expect(api.lastPrBase, 'main');
    });

    test('team slug collision fails before write', () async {
      final api = FakeGithubApi(
        upstreamIndexJson: '{"teams":[{"slug":"platform"}]}',
      );
      final publisher = GithubRegistryPublisher(api: api);

      await expectLater(
        publisher.publishTeam(
          upstream: kDefaultTeamHubRegistry,
          slug: 'platform',
          teamJson: {
            'key': 'hhoao/teampilot/team-hub/platform',
            'name': 'Platform',
            'description': '',
            'category': '',
            'updatedAt': 1,
            'roster': <Object?>[],
          },
          token: 't',
        ),
        throwsA(
          isA<HubPublishException>().having(
            (e) => e.code,
            'code',
            HubPublishErrorCode.slugCollision,
          ),
        ),
      );
      expect(api.writtenPaths, isEmpty);
      expect(api.ensuredFork, isFalse);
    });
  });
}
