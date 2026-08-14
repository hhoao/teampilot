import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/services/cli/registry/capabilities/provider_capability.dart';
import 'package:teampilot/services/cli/cursor/provider/cursor_home_layout.dart';
import 'package:teampilot/services/cli/cursor/provider/cursor_live_import.dart';

import '../../../support/in_memory_filesystem.dart';

void main() {
  test('loadSnapshot finds auth.json under Windows APPDATA', () async {
    final winContext = p.Context(style: p.Style.windows);
    final fs = InMemoryFilesystem(pathContext: winContext);
    final layout = CursorHomeLayout(pathContext: winContext);
    const home = r'C:\Users\haung';
    const appData = r'C:\Users\haung\AppData\Roaming';
    await fs.writeString(
      winContext.join(appData, 'Cursor', 'auth.json'),
      '{"accessToken":"at1","refreshToken":"rt1"}',
    );

    final snapshot = await CursorLiveImport.loadSnapshot(
      ProviderCatalogLoadContext(
        fs: fs,
        homeDirectory: home,
        cwd: home,
        usePosixPaths: false,
        platformEnv: const {'APPDATA': appData},
      ),
    );

    expect(snapshot.providers, isNotEmpty);
    expect(snapshot.sources, contains('live'));
    expect(snapshot.providers.single.isOfficial, isTrue);
    expect(
      layout
          .globalAuthJsonCandidates(
            home,
            platformEnv: const {'APPDATA': appData},
          )
          .first,
      winContext.join(appData, 'Cursor', 'auth.json'),
    );
  });
}
