import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/services/chat/launch/staging/manifest/launch_manifest.dart';
import 'package:teampilot/services/chat/launch/staging/manifest/manifest_executor.dart';
import 'package:teampilot/services/chat/launch/staging/manifest/manifest_filesystem.dart';
import 'package:teampilot/services/cli/cursor/provider/cursor_session_config_dir.dart';
import 'package:teampilot/services/cli/cursor/provider/cursor_windows_home_junction.dart';
import 'package:teampilot/services/storage/windows_cli_runtime_junction.dart';

import '../../../support/in_memory_filesystem.dart';

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

    test(
      'junction after overlay writes keeps files readable through canonical home',
      () async {
        final ctx = p.Context(style: p.Style.windows);
        final disk = InMemoryFilesystem(pathContext: ctx);
        final manifest = LaunchManifest(pathContext: ctx);
        final overlay = ManifestFilesystem(
          manifest: manifest,
          readDelegate: disk,
          pathContext: ctx,
        );
        const workRoot = r'C:\Users\haung\AppData\Roaming\com.hhoa\TeamPilot';
        final canonical = ctx.join(
          workRoot,
          r'workspace\workspaces\4f8f51a9-77cd-40f5-98ef-b678741b7b2e'
          r'\sessions\05224e22-0080-4e5c-a528-93c681f77998\runtime\cursor\home',
        );
        const localRoot = r'C:\Users\haung\AppData\Local\com.hhoa.teampilot';
        final skillRel = ctx.join(
          '.cursor',
          '.teampilot-managed',
          'team-builder',
          'SKILL.md',
        );
        await overlay.writeString(ctx.join(canonical, skillRel), 'skill-body');
        await WindowsCliRuntimeJunction.ensurePhysicalHome(
          fs: overlay,
          spec: cursorSpec,
          canonicalHome: canonical,
          localAppDataRoot: localRoot,
          forceJunction: true,
        );
        await const ManifestExecutor().flush(
          manifest: manifest,
          targetFs: disk,
          sourceFs: disk,
          symlinkProjectionRoot: workRoot,
          homeRoot: workRoot,
        );
        expect(
          await disk.readString(ctx.join(canonical, skillRel)),
          'skill-body',
        );
      },
    );
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
      final home =
          r'C:\Users\haung\AppData\Roaming\com.hhoa\TeamPilot'
          r'\workspace\workspaces\4f8f51a9-77cd-40f5-98ef-b678741b7b2e'
          r'\sessions\05224e22-0080-4e5c-a528-93c681f77998\runtime\cursor\home';
      expect(
        CursorWindowsHomeJunction.needsJunction(home),
        Platform.isWindows ? isTrue : isFalse,
      );
    });

    test('marker path sits next to canonical home junction', () {
      final canonical = Platform.isWindows
          ? r'C:\tp\sessions\s1\runtime\cursor\home'
          : p.join(
              p.separator,
              'tp',
              'sessions',
              's1',
              'runtime',
              'cursor',
              'home',
            );
      expect(
        CursorWindowsHomeJunction.markerPathForCanonicalHome(canonical),
        p.join(p.dirname(canonical), 'runtime-home'),
      );
    });
  });
}
