import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/discoverable_member.dart';
import 'package:teampilot/services/expert_hub/expert_hub_source.dart';
import 'package:teampilot/services/expert_hub/git_registry_expert_hub_source.dart';

import '../../support/post_frame_test_harness.dart';

void main() {
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  test('default registry points to teampilot-resources', () {
    expect(kDefaultExpertHubRegistry.fullName, 'hhoao/teampilot-resources');
    expect(
      kDefaultExpertHubRegistry.catalogPrefix,
      'hhoao/teampilot-resources/member-hub',
    );
  });

  Map<Uri, String> network() {
    const reg = kDefaultExpertHubRegistry;
    return {
      reg.rawUri('index.json'): jsonEncode({
        'members': ['security-reviewer'],
      }),
      reg.rawUri('members/security-reviewer/member.json'): jsonEncode({
        'key': 'ignored',
        'name': 'Security Reviewer',
        'description': 'Reviews code for security issues',
        'category': 'Development',
        'updatedAt': 2,
        'member': {
          'name': 'security-reviewer',
          'responsibilities': 'Review for security vulnerabilities only.',
          'playbook': 'Check auth, injection, and secrets handling.',
        },
      }),
    };
  }

  test('fetches members from the registry and stamps keys', () async {
    final net = network();
    final source = GitRegistryExpertHubSource(fetch: (uri) async => net[uri]);

    final members = await source.fetchMembers();
    expect(members, hasLength(1));
    expect(members.single.key, 'hhoao/teampilot-resources/member-hub/security-reviewer');
    expect(members.single.source, ExpertMemberSource.registry);
    expect(members.single.name, 'Security Reviewer');
    expect(
      members.single.member.responsibilities,
      'Review for security vulnerabilities only.',
    );

    final categories = await source.categories();
    expect(categories, ['Development']);
  });

  test('second call without forceRefresh serves from cache', () async {
    final net = network();
    var calls = 0;
    final source = GitRegistryExpertHubSource(
      fetch: (uri) async {
        calls++;
        return net[uri];
      },
    );

    await source.fetchMembers();
    final firstCalls = calls;
    expect(firstCalls, greaterThan(0));

    final cached = await source.fetchMembers();
    expect(cached, hasLength(1));
    expect(calls, firstCalls, reason: 'cache hit must not re-fetch');
  });

  test('forceRefresh re-fetches the network', () async {
    final net = network();
    var calls = 0;
    final source = GitRegistryExpertHubSource(
      fetch: (uri) async {
        calls++;
        return net[uri];
      },
    );
    await source.fetchMembers();
    final before = calls;
    await source.fetchMembers(forceRefresh: true);
    expect(calls, greaterThan(before));
  });
}
