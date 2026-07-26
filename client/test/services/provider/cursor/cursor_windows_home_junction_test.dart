import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/services/provider/cursor/cursor_session_config_dir.dart';
import 'package:teampilot/services/provider/cursor/cursor_windows_home_junction.dart';
import 'package:teampilot/services/storage/windows_cli_runtime_junction.dart';

void main() {
  group('WindowsCliRuntimeJunction', () {
    const cursorSpec = WindowsCliRuntimeJunctionSpec(
      toolId: 'cursor',
      homeSegment: 'home',
      maxPathSuffixFromHome: 134,
    );

    test('physicalHomePath nests under cli-runtime-homes/{toolId}', () {
      final canonical = r'C:\long\session\runtime\cursor\home';
      final physical = WindowsCliRuntimeJunction.physicalHomePath(
        spec: cursorSpec,
        localAppDataRoot: r'C:\Users\haung\AppData\Local\com.hhoa.teampilot',
        canonicalHome: canonical,
      );
      expect(physical.length, lessThan(130));
      expect(physical, contains(p.join('cli-runtime-homes', 'cursor')));
      expect(physical, endsWith(CursorSessionConfigDir.homeSegment));
    });
  });

  group('CursorWindowsHomeJunction', () {
    test('needsJunction is false for short canonical homes', () {
      expect(
        CursorWindowsHomeJunction.needsJunction(
          r'C:\tp\workspace\workspaces\1\sessions\2\runtime\cursor\home',
        ),
        isFalse,
      );
    });

    test('needsJunction is true for TeamPilot-like deep homes on Windows', () {
      final home = r'C:\Users\haung\AppData\Roaming\com.hhoa\TeamPilot'
          r'\workspace\workspaces\4f8f51a9-77cd-40f5-98ef-b678741b7b2e'
          r'\sessions\05224e22-0080-4e5c-a528-93c681f77998\runtime\cursor\home';
      expect(
        CursorWindowsHomeJunction.needsJunction(home),
        Platform.isWindows ? isTrue : isFalse,
      );
    });

    test('marker path sits next to canonical home junction', () {
      final canonical = r'C:\tp\sessions\s1\runtime\cursor\home';
      expect(
        CursorWindowsHomeJunction.markerPathForCanonicalHome(canonical),
        r'C:\tp\sessions\s1\runtime\cursor\runtime-home',
      );
    });
  });
}
