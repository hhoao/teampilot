import '../../models/discoverable_member.dart';
import '../../models/team_config.dart';
import '../expert_hub/expert_hub_source.dart';
import '../team_hub/team_hub_source.dart';
import 'bundle_provenance_lookup.dart';
import 'expert_publish_mapper.dart';
import 'github_registry_publisher.dart';
import 'hub_publish_credentials_store.dart';
import 'hub_publish_record_store.dart';
import 'team_profile_publish_mapper.dart';

/// Thin facade: resolve token → map → publish → record badge.
class HubPublishService {
  HubPublishService({
    required HubPublishCredentialsStore credentials,
    required HubPublishRecordStore records,
    required GithubRegistryPublisher publisher,
    required BundleProvenanceLookup lookup,
    int Function()? nowMs,
  }) : _credentials = credentials,
       _records = records,
       _publisher = publisher,
       _lookup = lookup,
       _nowMs = nowMs ?? _defaultNowMs;

  static int _defaultNowMs() => DateTime.now().millisecondsSinceEpoch;

  final HubPublishCredentialsStore _credentials;
  final HubPublishRecordStore _records;
  final GithubRegistryPublisher _publisher;
  final BundleProvenanceLookup _lookup;
  final int Function() _nowMs;

  Future<HubPublishResult> publishExpert({
    required DiscoverableMember member,
    required String slug,
    ExpertHubRegistry upstream = kDefaultExpertHubRegistry,
    String? author,
    String? category,
    List<String>? skillIds,
  }) async {
    final token = await _requireToken();
    final key = '${upstream.fullName}/$slug';
    final mapped = ExpertPublishMapper.map(
      member: member,
      lookup: _lookup,
      key: key,
      author: author,
      category: category,
      skillIds: skillIds,
      updatedAt: _nowMs(),
    );
    if (mapped is PublishBlockedExpert) {
      throw HubPublishException(
        HubPublishErrorCode.publishBlocked,
        mapped.reasons.join('\n'),
      );
    }
    final ready = mapped as PublishReadyExpert;
    final result = await _publisher.publishExpert(
      upstream: upstream,
      slug: slug,
      memberJson: ready.member.toJson(),
      token: token,
    );
    await _records.upsert(
      HubPublishRecord(
        kind: HubPublishKind.expert,
        registryFullName: result.registryFullName,
        slug: result.slug,
        prUrl: result.prUrl,
        publishedAtMs: _nowMs(),
      ),
    );
    return result;
  }

  Future<HubPublishResult> publishTeam({
    required TeamProfile team,
    required String slug,
    required String category,
    required Map<String, String> expertKeyRemap,
    TeamHubRegistry upstream = kDefaultTeamHubRegistry,
    String? author,
  }) async {
    final token = await _requireToken();
    final key = '${upstream.fullName}/$slug';
    final mapped = TeamProfilePublishMapper.map(
      team: team,
      expertKeyRemap: expertKeyRemap,
      lookup: _lookup,
      key: key,
      category: category,
      author: author,
      updatedAt: _nowMs(),
    );
    if (mapped is PublishBlocked) {
      throw HubPublishException(
        HubPublishErrorCode.publishBlocked,
        mapped.reasons.join('\n'),
      );
    }
    final ready = mapped as PublishReadyTeam;
    final result = await _publisher.publishTeam(
      upstream: upstream,
      slug: slug,
      teamJson: ready.team.toJson(),
      token: token,
    );
    await _records.upsert(
      HubPublishRecord(
        kind: HubPublishKind.team,
        registryFullName: result.registryFullName,
        slug: result.slug,
        prUrl: result.prUrl,
        publishedAtMs: _nowMs(),
      ),
    );
    return result;
  }

  Future<String> _requireToken() async {
    final token = await _credentials.resolveToken();
    if (token == null || token.isEmpty) {
      throw const HubPublishException(
        HubPublishErrorCode.missingToken,
        'GitHub token required to publish',
      );
    }
    return token;
  }
}
