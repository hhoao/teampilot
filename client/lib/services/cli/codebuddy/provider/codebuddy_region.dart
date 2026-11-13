import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../../../io/filesystem.dart';

/// Cloud region a CodeBuddy account belongs to, and the CLI state that
/// selects it.
///
/// The CLI resolves its cloud from settings `env`, then process env, then the
/// product configuration, then the account's auth `domain` — except that a
/// region cached under `<configDir>/local_storage` outranks the login's own
/// domain. Config dirs outlive account switches (a session dir is reused on
/// relaunch, provider login homes on re-login), so that cache is what survives
/// a switch and sends the new account's token to the previous account's cloud:
/// the API answers 401, ACP reports `authRequired`, and the UI claims the
/// agent is not logged in.
///
/// TeamPilot therefore states the region itself whenever it injects a stored
/// token (`CodebuddyAuthStore.accountEnvironment`), and [clearCachedRegion]
/// drops the cached value so a launch on the machine login re-derives it.
enum CodebuddyRegion {
  internal('internal'),
  external('external');

  const CodebuddyRegion(this.value);

  /// Value for `CODEBUDDY_INTERNET_ENVIRONMENT`.
  final String value;

  static const envKey = 'CODEBUDDY_INTERNET_ENVIRONMENT';

  /// `localStorage` key the CLI caches the resolved region under.
  static const cacheKey = 'CodeBuddy-Environment-Cache';

  /// Account domain families per cloud, mirroring `product.json` →
  /// `authentication.attributes`.
  static const _domesticFamilies = ['codebuddy.cn', 'workbuddy.cn'];
  static const _internationalFamilies = ['codebuddy.ai'];

  static CodebuddyRegion? forAuthDomain(String? domain) {
    final host = domain?.trim().toLowerCase() ?? '';
    if (host.isEmpty) return null;
    if (_domesticFamilies.any((family) => _inFamily(host, family))) {
      return internal;
    }
    if (_internationalFamilies.any((family) => _inFamily(host, family))) {
      return external;
    }
    return null;
  }

  static bool _inFamily(String host, String family) =>
      host == family || host.endsWith('.$family');

  /// Removes the CLI's cached region from [configDir]. Missing entries are a
  /// no-op, so callers clear unconditionally before every launch.
  static Future<void> clearCachedRegion(Filesystem fs, String configDir) =>
      fs.removeRecursive(cacheEntryPath(fs.pathContext, configDir));

  /// `localStorage` entry file the CLI caches [cacheKey] under: the extension
  /// names entries `entry_<md5(key)>.info`.
  static String cacheEntryPath(p.Context pathContext, String configDir) =>
      pathContext.join(
        configDir,
        'local_storage',
        'entry_${md5.convert(utf8.encode(cacheKey))}.info',
      );
}
