import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/services/session_sync/session_dir_change_parser.dart';

void main() {
  test('extracts workspaces for sessions directory changes', () {
    final ctx = p.Context(style: p.Style.posix);
    const root = '/home/u/.local/share/com.hhoa.teampilot/workspace';
    final ids = workspaceIdsFromSessionChangeDirs(
      [
        '$root/workspaces/ws-1/sessions',
        '$root/workspaces/ws-1/sessions/s-1',
        '$root/workspaces/ws-2/manifest.json',
        '/tmp/other/workspaces/ws-3/sessions',
      ],
      workspaceRoot: root,
      pathContext: ctx,
    );

    expect(ids, {'ws-1'});
  });

  test('ignores the workspace root itself', () {
    final ctx = p.Context(style: p.Style.posix);
    const root = '/tp/workspace';
    final ids = workspaceIdsFromSessionChangeDirs(
      ['$root/workspaces/ws-1', '$root/workspaces/ws-2/session-groups.json'],
      workspaceRoot: root,
      pathContext: ctx,
    );

    expect(ids, isEmpty);
  });
}
