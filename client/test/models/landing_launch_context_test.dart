import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/landing_launch_context.dart';
import 'package:teampilot/models/team_config.dart';

void main() {
  test('copyWith can clear presetId and set custom cli', () {
    const base = LandingLaunchContext(isPersonal: true, presetId: 'p1');
    final next = base.copyWith(
      presetId: null,
      cli: CliTool.cursor,
      provider: 'cursor-account',
    );
    expect(next.presetId, isNull);
    expect(next.cli, CliTool.cursor);
    expect(next.provider, 'cursor-account');
  });

  test('personal context always clears generate launch', () {
    const draft = LandingLaunchContext(isPersonal: true, generateLaunch: true);
    expect(draft.generateLaunch, isFalse);
    expect(draft.copyWith(isPersonal: false, generateLaunch: true).generateLaunch, isTrue);
    expect(draft.copyWith(isPersonal: true).generateLaunch, isFalse);
  });
}
