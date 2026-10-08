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
  final _retiredHomeContexts = <String, Set<RuntimeContext>>{};
  final _targetOperations = <String, Future<void>>{};
  RuntimeContext? _home;

  /// Materialize + cache the home context. Call once at bootstrap.
  Future<void> ensureHome() async {
    final target = _homeTarget;
    await _withTargetOperation(target.id, () async {
      _home = await _resolve(target, cache: true);
    });
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
      return _resolve(target, cache: true);
    });
  }

  Future<RuntimeContext> _resolve(
    RuntimeTarget target, {
    required bool cache,
  }) async {
    final profileId = target.sshProfileId;
    final sshProfile = profileId != null
        ? _sshProfileById?.call(profileId)
        : null;
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
      final next = await _resolve(homeTarget, cache: false);

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
