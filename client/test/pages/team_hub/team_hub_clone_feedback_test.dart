import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/l10n/app_localizations_en.dart';
import 'package:teampilot/pages/team_hub/team_hub_clone_feedback.dart';
import 'package:teampilot/services/team/team_clone_service.dart';

void main() {
  final l10n = AppLocalizationsEn();

  test('success with no deps uses simple message', () {
    final msg = teamHubCloneToastMessage(
      l10n,
      teamName: 'Squad',
      result: const CloneResult(
        teamId: 'id',
        installed: CloneDepInstallSummary(),
        failedDeps: [],
      ),
    );
    expect(msg, 'Cloned "Squad".');
    expect(
      teamHubCloneToastIsWarning(
        const CloneResult(
          teamId: 'id',
          installed: CloneDepInstallSummary(),
          failedDeps: [],
        ),
      ),
      isFalse,
    );
  });

  test('success with deps lists install counts', () {
    final msg = teamHubCloneToastMessage(
      l10n,
      teamName: 'Squad',
      result: const CloneResult(
        teamId: 'id',
        installed: CloneDepInstallSummary(
          skillIds: ['a', 'b'],
          pluginIds: ['p'],
        ),
        failedDeps: [],
      ),
    );
    expect(
      msg,
      'Cloned "Squad". Installed 2 skills, 1 plugins, and 0 MCP servers.',
    );
  });

  test('partial failure is warning and names failed deps', () {
    final result = CloneResult(
      teamId: 'id',
      installed: const CloneDepInstallSummary(skillIds: ['a']),
      failedDeps: const [
        DependencyFailure(DependencyKind.skill, 'missing-skill'),
      ],
    );
    final msg = teamHubCloneToastMessage(l10n, teamName: 'Squad', result: result);
    expect(msg, contains('missing-skill'));
    expect(teamHubCloneToastIsWarning(result), isTrue);
  });
}
