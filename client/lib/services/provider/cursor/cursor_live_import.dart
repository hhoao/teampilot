import '../../../models/provider_presets/cursor_provider_presets.dart';
import '../../cli/registry/capabilities/provider_catalog_capability.dart';
import 'cursor_auth_artifacts.dart';
import 'cursor_home_layout.dart';

/// Scans the user's global Cursor home for a logged-in account.
abstract final class CursorLiveImport {
  CursorLiveImport._();

  static Future<ProviderCatalogSnapshot> loadSnapshot(
    ProviderCatalogLoadContext context,
  ) async {
    final home = context.homeDirectory.trim();
    if (home.isEmpty) return const ProviderCatalogSnapshot();

    final layout = CursorHomeLayout(pathContext: context.fs.pathContext);
    final authPath = layout.authJson(home);
    final authContent = await context.fs.readString(authPath);
    if (!CursorAuthArtifacts.authJsonIndicatesLoggedIn(authContent ?? '')) {
      return const ProviderCatalogSnapshot();
    }

    final now = context.resolvedNow();
    final preset = CursorProviderPresets.account.template;
    return ProviderCatalogSnapshot(
      providers: [preset.copyWith(createdAt: now, updatedAt: now)],
      sources: const ['live'],
    );
  }
}
