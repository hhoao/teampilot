import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/right_tool_open_set.dart';
import 'package:teampilot/widgets/right_tools/right_tool_ids.dart';

void main() {
  test('UI catalog ids are all in the persistence known set', () {
    const catalog = [
      RightToolIds.members,
      RightToolIds.fileTree,
      RightToolIds.git,
      RightToolIds.mailbox,
      RightToolIds.board,
      RightToolIds.search,
    ];
    for (final id in catalog) {
      expect(
        RightToolOpenSet.knownIds,
        contains(id),
        reason: '$id must stay in RightToolOpenSet.knownIds',
      );
    }
  });

  test('team seed ids share the persistence source of truth', () {
    expect(RightToolIds.teamSeedIds, RightToolOpenSet.teamSeedIds);
  });
}
