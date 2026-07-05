import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/expert_hub_cubit.dart';
import 'package:teampilot/models/discoverable_member.dart';
import 'package:teampilot/models/discoverable_team.dart';
import 'package:teampilot/services/expert_hub/composite_expert_hub_source.dart';
import 'package:teampilot/services/expert_hub/expert_hub_source.dart';
import 'package:teampilot/services/expert_hub/member_clone_service.dart';

class _FakeSource extends CompositeExpertHubSource {
  _FakeSource(this.members)
    : super(builtIns: members, registry: _EmptyRegistry());

  final List<DiscoverableMember> members;
  int fetchCount = 0;

  @override
  Future<List<DiscoverableMember>> fetchMembers({
    bool forceRefresh = false,
  }) async {
    fetchCount++;
    return members;
  }
}

class _EmptyRegistry implements ExpertHubSource {
  @override
  Future<List<DiscoverableMember>> fetchMembers({bool forceRefresh = false}) =>
      Future.value(const []);

  @override
  Future<List<String>> categories({bool forceRefresh = false}) =>
      Future.value(const []);
}

DiscoverableMember _m(
  String name,
  String cat,
  int updated, {
  String keyPrefix = 'o/r',
  ExpertMemberSource source = ExpertMemberSource.registry,
}) => DiscoverableMember(
  key: '$keyPrefix/${name.toLowerCase()}',
  name: name,
  description: 'desc of $name',
  category: cat,
  source: source,
  updatedAt: updated,
  member: DiscoverableTeamMember(name: name.toLowerCase(), prompt: 'p'),
);

void main() {
  late _FakeSource source;
  late ExpertHubCubit cubit;

  setUp(() {
    source = _FakeSource([
      _m('Beta', 'AI', 30),
      _m('Alpha', 'AI', 10),
      _m('Gamma', 'Testing', 20),
    ]);
    cubit = ExpertHubCubit(
      source: source,
      loadFavorites: () async => {'o/r/alpha'},
      saveFavoriteToggle: (key) async => true,
      memberCloneService: MemberCloneService(installSkill: (_) async => null),
      launchProfiles: () => throw UnimplementedError('not used in filter tests'),
    );
  });

  test('favoritesOnly filter narrows to favorite keys', () async {
    await cubit.load();
    cubit.setFavoritesOnly(true);
    expect(cubit.visibleMembers.map((m) => m.name), ['Alpha']);
    cubit.setFavoritesOnly(false);
    expect(cubit.visibleMembers, hasLength(3));
  });
}
