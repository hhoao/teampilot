import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/expert_hub/expert_hub_source.dart';
import 'package:teampilot/services/expert_hub/git_registry_expert_hub_source.dart';

void main() {
  test(
    'reports a safe source failure when the registry index is unavailable',
    () async {
      final source = GitRegistryExpertHubSource(fetch: (_) async => null);

      final results = await (source as ExpertHubSourceContributions)
          .fetchMemberSources();

      expect(results.single.items, isEmpty);
      expect(results.single.failure, isNotNull);
      expect(results.single.failure!.sourceId, 'expert-registry');
      expect(results.single.failure!.message, isNot(contains('response body')));
    },
  );
}
