import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/member_config/member_config_detail.dart';

void main() {
  test('MemberConfigDetail.none marks an absent config dir', () {
    const detail = MemberConfigDetail.none(cli: CliTool.claude);
    expect(detail.sourceLayer, MemberConfigSourceLayer.none);
    expect(detail.resolvedDir, '');
    expect(detail.skills, isEmpty);
    expect(detail.mcpServers, isEmpty);
    expect(detail.plugins, isEmpty);
    expect(detail.settings, isEmpty);
    expect(detail.warnings, isEmpty);
    expect(detail.hasConfig, isFalse);
  });

  test('hasConfig is true when source layer is runtime or team', () {
    const detail = MemberConfigDetail(
      cli: CliTool.claude,
      resolvedDir: '/tp/teams-runtime/t/claude',
      sourceLayer: MemberConfigSourceLayer.team,
    );
    expect(detail.hasConfig, isTrue);
  });
}
