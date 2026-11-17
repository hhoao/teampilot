import 'dart:async';

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
    SshProfile? Function(String id)? workProfileById,
    TermuxPathCache Function()? termuxPathCache,
    Future<void> Function(String targetId)? onEvict,
  }) : _resolver = resolver,
       _homeTarget = homeTarget,
       _sshProfileById = sshProfileById,
       _workProfileById = workProfileById,
       _termuxPathCache = termuxPathCache,
       _onEvict = onEvict;

  final RuntimeContextResolver _resolver;
  RuntimeTarget _homeTarget;
  /// Device-local home-binding catalog (A source). Resolves the current SSH
  /// home target and its cached paths. Home binding must never read from the
  /// home-plane workload catalog (B source).
  final SshProfile? Function(String id)? _sshProfileById;
  /// Work-plane resolver (combined B-first + A-fallback). Resolves `ssh:<id>`
  /// folder/workspace targets, which name home-plane workload hosts (B), with
  /// an A-source fallback for SSH-home / offline binding. When omitted, falls
  /// back to [_sshProfileById] so standalone/test registries keep working.
  final SshProfile? Function(String id)? _workProfileById;
  final TermuxPathCache Function()? _termuxPathCache;
  final Future<void> Function(String targetId)? _onEvict;

  final _cache = <String, RuntimeContext>{};
  final _retiredHomeContexts = <String, Set<RuntimeContext>>{};
  final _targetOperations = <String, Future<void>>{};
  RuntimeContext? _home;

  /// Materialize + cache the home context. Call once at bootstrap.
  Future<void> ensureHome() async {
    final target = _homeTarget;
    await _withTargetOperation(target.id, () async {
      _home = await _resolve(target, cache: true, isHome: true);
    });
  }

  /// Pick the profile resolver for [target]: the home target resolves from the
  /// device-local A source (home binding), every work-plane target resolves
  /// from the combined B-first + A-fallback resolver. This is the single point
  /// where the two SSH profile sources are kept apart for context resolution.
  SshProfile? _profileFor(RuntimeTarget target, {required bool isHome}) {
    final profileId = target.sshProfileId;
    if (profileId == null) return null;
    final resolver = isHome
        ? _sshProfileById
        : (_workProfileById ?? _sshProfileById);
    return resolver?.call(profileId);
  }

  /// Materialize + publish a cached home context without any network I/O.
  ///
  /// Used when the home is unreachable or the bounded connect attempt has not
  /// completed: the shell must still be able to build on the persisted
  /// `lastHome`/`lastAppDataRoot` paths. Reuses the already-materialized home
  /// when there is one (a live resolve always wins).
  ///
  /// Deliberately NOT serialized through [_withTargetOperation]: a live
  /// [ensureHome] that hit its budget may still be running, and queueing here
  /// would reintroduce the unbounded splash wait the bounded attempt exists to
  /// avoid. A live resolve that finishes later overwrites this value.
  Future<RuntimeContext> ensureHomeCached() async {
    final target = _homeTarget;
    final cached = await _resolver.resolveCached(
      target,
      // Cached home paths come from the device-local A source home profile.
      sshProfile: _profileFor(target, isHome: true),
    );
    _home ??= cached;
    return _home!;
  }

  /// The control-plane context. Throws if [ensureHome] has not run.
  RuntimeContext home() =>
      _home ??
      (throw StateError('home context not initialised; call ensureHome()'));

  /// Work-plane context for [target], materialized lazily and cached by id.
  Future<RuntimeContext> forTarget(RuntimeTarget target) {
    return _withTargetOperation(target.id, () async {
      final cached = _cache[target.id];
      if (cached != null) return cached;
      return _resolve(target, cache: true, isHome: false);
    });
  }

  Future<RuntimeContext> _resolve(
    RuntimeTarget target, {
    required bool cache,
    required bool isHome,
  }) async {
    final sshProfile = _profileFor(target, isHome: isHome);
    final termuxCache = target.kind == RuntimeKind.termux
        ? _termuxPathCache?.call()
        : null;
    final ctx = await _resolver.resolve(
      target,
      sshProfile: sshProfile,
      cachedHome: termuxCache?.home ?? sshProfile?.lastHome,
      cachedAppDataRoot:
          termuxCache?.appDataRoot ?? sshProfile?.lastAppDataRoot,
    );
    if (cache) _cache[target.id] = ctx;
    return ctx;
  }

  /// Evict a cached context.
  ///
  /// When [notifyEvict] is true (default), remote/SSH targets invoke [onEvict]
  /// (typically disconnects the storage pool). Pass `false` for home reinstall
  /// that only needs a fresh [RuntimeContext] wrapper while keeping the live
  /// SSH pool (Android Connect → reload must not tear down the just-connected
  /// transport).
  Future<void> dispose(String targetId, {bool notifyEvict = true}) {
    return _withTargetOperation(targetId, () async {
      final ctx = _cache.remove(targetId);
      final retired = _retiredHomeContexts.remove(targetId);
      if (ctx == null && (retired == null || retired.isEmpty)) return;
      if (identical(_home, ctx)) _home = null;
      if (!notifyEvict) return;
      if (ctx != null) await _notifyEvicted(ctx);
      for (final old in retired ?? const <RuntimeContext>{}) {
        if (!identical(old, ctx)) await _notifyEvicted(old);
      }
    });
  }

  /// Evict [context] only if it is still the cached instance for its target.
  ///
  /// Safe to call after a newer context for the same target id was already
  /// materialized (e.g. a HomeStorage retire callback firing after a same-id
  /// rebind): the stale instance is a no-op and the replacement stays cached.
  Future<void> disposeContext(
    RuntimeContext context, {
    bool notifyEvict = true,
  }) {
    return _withTargetOperation(context.target.id, () async {
      if (identical(_cache[context.target.id], context)) {
        _cache.remove(context.target.id);
        if (identical(_home, context)) _home = null;
        if (notifyEvict) await _notifyEvicted(context);
        return;
      }
      final retired = _retiredHomeContexts[context.target.id];
      if (retired == null || !retired.remove(context)) return;
      if (retired.isEmpty) _retiredHomeContexts.remove(context.target.id);
      // Same-target home rebinds intentionally keep the shared SSH pool alive.
    });
  }

  /// Rebind the home target (user switched home device).
  ///
  /// Resolution is transactional: the previous home remains cached and
  /// published if resolving the replacement fails. Operations for one target
  /// are serialized so a concurrent [forTarget] cannot overwrite the context
  /// selected by this rebind.
  Future<void> rebindHome(RuntimeTarget homeTarget) {
    return _withTargetOperation(homeTarget.id, () async {
      final previousHome = _home;
      final previous = _cache[homeTarget.id];
      final next = await _resolve(homeTarget, cache: false, isHome: true);

      if (previous != null && !identical(previousHome, previous)) {
        await _notifyEvicted(previous);
      }
      _cache[homeTarget.id] = next;
      if (identical(previousHome, previous) && previous != null) {
        (_retiredHomeContexts[homeTarget.id] ??= <RuntimeContext>{}).add(
          previous,
        );
      }
      _homeTarget = homeTarget;
      _home = next;
    });
  }

  Future<void> _notifyEvicted(RuntimeContext context) async {
    if (context.storageIsRemote || usesSshTransport(context.target.kind)) {
      await _onEvict?.call(context.target.id);
    }
  }

  Future<T> _withTargetOperation<T>(
    String targetId,
    Future<T> Function() operation,
  ) {
    final previous = _targetOperations[targetId] ?? Future<void>.value();
    final done = Completer<void>();
    _targetOperations[targetId] = done.future;
    return () async {
      await previous;
      try {
        return await operation();
      } finally {
        done.complete();
        if (identical(_targetOperations[targetId], done.future)) {
          _targetOperations.remove(targetId);
        }
      }
    }();
  }
}
