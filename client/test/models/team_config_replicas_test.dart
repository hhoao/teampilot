import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';

void main() {
  test('replicas defaults to 1 and round-trips when > 1', () {
    const m = TeamMemberConfig(id: 'builder', name: 'Builder');
    expect(m.replicas, 1);

    const r = TeamMemberConfig(id: 'builder', name: 'Builder', replicas: 3);
    expect(r.replicas, 3);
    expect(TeamMemberConfig.fromJson(r.toJson()).replicas, 3);
    expect(m.toJson().containsKey('replicas'), isFalse);
  });
}
