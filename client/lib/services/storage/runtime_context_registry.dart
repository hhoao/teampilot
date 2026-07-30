import '../../models/runtime_target.dart';
import '../../models/ssh_profile.dart';
import 'runtime_context.dart';
import 'runtime_context_resolver.dart';

typedef TermuxPathCache = ({String? home, String? appDataRoot});

/// Owns the live runtime contexts. The home context (control plane) is
/// materialized once at bootstrap and cached; work-plane contexts are
/// materialized lazily per target id and cached so multiple workspaces/sessions
/// on the same machine reuse one context (and its SSHClient).
class RuntimeContextRegistry {
  RuntimeContextRegistry({
    required RuntimeContextResolver resolver,
    required RuntimeTarget homeTarget,
    SshProfile? Function(String id)? sshProfileById,
    TermuxPathCache Function()? termuxPathCache,
    Future<void> Function(String targetId)? onEvict,
  }) : _resolver = resolver,
       _homeTarget = homeTarget,
       _sshProfileById = sshProfileById,
       _termuxPathCache = termuxPathCache,
       _onEvict = onEvict;

  final RuntimeContextResolver _resolver;
  RuntimeTarget _homeTarget;
  final SshProfile? Function(String id)? _sshProfileById;
  final TermuxPathCache Function()? _termuxPathCache;
  final Future<void> Function(String targetId)? _onEvict;

  final _cache = <String, RuntimeContext>{};
  RuntimeContext? _home;

  /// Materialize + cache the home context. Call once at bootstrap.
  Future<void> ensureHome() async {
    _home = await forTarget(_homeTarget);
  }

  /// The control-plane context. Throws if [ensureHome] has not run.
  RuntimeContext home() =>
      _home ??
      (throw StateError('home context not initialised; call ensureHome()'));

  /// Work-plane context for [target], materialized lazily and cached by id.
  Future<RuntimeContext> forTarget(RuntimeTarget target) async {
    final cached = _cache[target.id];
    if (cached != null) return cached;
    final profileId = target.sshProfileId;
    final termuxCache = target.kind == RuntimeKind.termux
        ? _termuxPathCache?.call()
        : null;
    final ctx = await _resolver.resolve(
      target,
      sshProfile: profileId != null ? _sshProfileById?.call(profileId) : null,
      cachedHome: termuxCache?.home,
      cachedAppDataRoot: termuxCache?.appDataRoot,
    );
    _cache[target.id] = ctx;
    return ctx;
  }

  /// Evict a cached context.
  ///
  /// When [notifyEvict] is true (default), remote/SSH targets invoke [onEvict]
  /// (typically disconnects the storage pool). Pass `false` for home reinstall
  /// that only needs a fresh [RuntimeContext] wrapper while keeping the live
  /// SSH pool (Android Connect → reload must not tear down the just-connected
  /// transport).
  Future<void> dispose(String targetId, {bool notifyEvict = true}) async {
    final ctx = _cache.remove(targetId);
    if (ctx == null) return;
    if (identical(_home, ctx)) _home = null;
    if (!notifyEvict) return;
    final shouldNotify =
        ctx.storageIsRemote || usesSshTransport(ctx.target.kind);
    if (shouldNotify) await _onEvict?.call(targetId);
  }

  /// Rebind the home target (user switched home device).
  Future<void> rebindHome(RuntimeTarget homeTarget) async {
    _homeTarget = homeTarget;
    _home = await forTarget(homeTarget);
  }
}
