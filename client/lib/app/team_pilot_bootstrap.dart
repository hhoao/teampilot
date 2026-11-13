import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../cubits/app_bootstrap_cubit.dart';
import '../cubits/connect_cubit.dart';
import '../cubits/home_connection_cubit.dart';
import '../l10n/l10n_extensions.dart';
import '../models/runtime_target.dart';
import '../pages/system/app_bootstrap_loading_page.dart';
import '../pages/system/bootstrap_startup_error_page.dart';
import '../services/app/boot_splash.dart';
import '../services/event/agent_presence_event.dart';
import '../services/event/agent_presence_projection.dart';
import '../services/event/agent_presence_sink.dart';
import '../services/event/agent_presence_transport_codec.dart';
import '../services/event/async_dispatcher.dart';
import '../services/event/event_publisher.dart';
import '../services/event/event_transport_client.dart';
import '../services/event/event_transport_controller.dart';
import '../services/event/event_transport_server.dart';
import '../services/event/session_lifecycle_transport_codec.dart';
import '../services/provider_usage/managed_provider_usage_auto_refresh.dart';
import '../services/ssh/ssh_connection_gate.dart';
import '../services/storage/home_storage.dart';
import '../services/storage/home_target_store.dart';
import '../utils/logging/logger.dart';
import '../utils/ui/yield_ui_frame.dart';
import 'app_shell.dart';

class TeamPilotBootstrap extends StatefulWidget {
  const TeamPilotBootstrap({
    super.key,
    required this.preferences,
    required this.nativeAppDataPath,
    required this.defaultWorkspaceDirectoryFuture,
    required this.homeIndexPrefetchFuture,
    required this.bootstrapCubit,
    required this.childBuilder,
  });

  final SharedPreferences preferences;
  final String nativeAppDataPath;
  final Future<String> defaultWorkspaceDirectoryFuture;
  final Future<void> homeIndexPrefetchFuture;
  final AppBootstrapCubit bootstrapCubit;
  final Widget Function(
    AppShell shell,
    Future<void> Function() stopEventTransport,
  )
  childBuilder;

  @override
  State<TeamPilotBootstrap> createState() => _TeamPilotBootstrapState();
}

class _TeamPilotBootstrapState extends State<TeamPilotBootstrap> {
  AppShell? _shell;
  Object? _error;
  var _retrying = false;
  ManagedProviderUsageAutoRefresh? _usageAutoRefresh;

  // Central event dispatcher: created once for the whole app lifecycle (not
  // per bootstrap retry), attached to the publisher so all publishes route
  // through it; stopped (drained) when the shell goes away.
  final AsyncDispatcher _eventDispatcher = AsyncDispatcher();

  // Pushed presence events: ONE projection per app lifecycle, exactly like the
  // dispatcher above — never per bootstrap retry (a retry must not leak a
  // second projection, nor a second family registration). Registered on the
  // dispatcher below and closed only after the dispatcher drains, in dispose.
  final AgentPresenceProjection _presenceProjection = AgentPresenceProjection();

  // Narrow per-shell publish edge onto the same dispatcher; buildAppShell
  // wraps it in a fresh PresenceEventBridge owned by that shell's cubit.
  late final AgentPresenceSink _presenceSink = DispatcherAgentPresenceSink(
    _eventDispatcher,
  );

  HomeStorage? _eventTransportHome;
  Future<void>? _eventTransportStopFuture;

  late final EventTransportController _eventTransportController =
      EventTransportController(
        createServer: () {
          final home = _eventTransportHome;
          if (home == null) {
            throw StateError('event-transport home storage not bound');
          }
          final server = EventTransportServer(
            dispatcher: _eventDispatcher,
            presence: _presenceProjection,
            fs: home.fs,
            advertisementPath: home.paths.eventTransportJson,
            codecs: [
              AgentPresenceTransportCodec(),
              SessionLifecycleTransportCodec(),
            ],
          );
          return CallbackEventTransportEndpoint(
            start: server.start,
            stop: server.stop,
          );
        },
        createClient:
            ({
              required Future<EventTransportByteChannel> Function() open,
              Future<bool> Function(Object error)? waitForRecovery,
            }) {
              final client = EventTransportClient(
                dispatcher: _eventDispatcher,
                presence: _presenceProjection,
                codecs: [
                  AgentPresenceTransportCodec(),
                  SessionLifecycleTransportCodec(),
                ],
                open: open,
                isExpectedFailure: isSshProfileDown,
                waitForRecovery: waitForRecovery,
                onError: (error, stackTrace) {
                  appLogger.w(
                    '[event-transport] client',
                    error: error,
                    stackTrace: stackTrace,
                  );
                },
              );
              return CallbackEventTransportEndpoint(
                start: client.start,
                stop: client.stop,
              );
            },
      );

  Future<void> _stopEventTransport() => _eventTransportStopFuture ??=
      _eventTransportController.apply(EventTransportRole.none);

  @override
  void initState() {
    super.initState();
    // Register before start(): routing keys on `event.eventKind.runtimeType`,
    // and every AgentPresenceKind value shares that runtimeType, so ONE
    // registration covers booting / working / idle (pinned by
    // test/services/event/agent_presence_family_registration_test.dart).
    _eventDispatcher.registerFamily<AgentPresenceKind>(
      AgentPresenceKind.working.runtimeType,
      _presenceProjection,
    );
    unawaited(_eventDispatcher.start());
    EventPublisher.instance.attach(_eventDispatcher);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_start());
    });
  }

  Future<void> _start() async {
    final bootSw = Stopwatch()..start();
    AppShell? builtShell;
    try {
      appLogger.i('[boot] +0ms TeamPilotBootstrap starting buildAppShell');
      builtShell = await buildAppShell(
        preferences: widget.preferences,
        nativeAppDataPath: widget.nativeAppDataPath,
        eventDispatcher: _eventDispatcher,
        defaultWorkspaceDirectoryFuture: widget.defaultWorkspaceDirectoryFuture,
        homeIndexPrefetchFuture: widget.homeIndexPrefetchFuture,
        bootstrapCubit: widget.bootstrapCubit,
        presenceProjection: _presenceProjection,
        presenceSink: _presenceSink,
        eventTransportController: _eventTransportController,
        bindEventTransportHome: (home) {
          _eventTransportHome = home;
        },
      );
      final shell = builtShell;
      if (!mounted) {
        await _eventTransportController.apply(EventTransportRole.none);
        await shell.memberPresenceCubit.close();
        await shell.homeConnectionCubit.close();
        await _teardownConnect(shell);
        await shell.managedProviderControlPlane.close();
        shell.cursorUsageApiClient.close();
        return;
      }
      final frameSw = Stopwatch()..start();
      await yieldUiFrame();
      appLogger.i(
        '[boot] +${bootSw.elapsedMilliseconds}ms shell built, '
        'bootstrap frame yielded +${frameSw.elapsedMilliseconds}ms',
      );
      await shell.bootstrapAppData();
      if (!mounted) {
        await _eventTransportController.apply(EventTransportRole.none);
        await shell.memberPresenceCubit.close();
        await shell.homeConnectionCubit.close();
        await _teardownConnect(shell);
        await shell.managedProviderControlPlane.close();
        shell.cursorUsageApiClient.close();
        return;
      }
      appLogger.i(
        '[boot] +${bootSw.elapsedMilliseconds}ms bootstrap complete '
        'workspaces=${shell.chatCubit.state.workspaces.length}',
      );
      // Build the app UI first so it paints underneath the splash overlay.
      // Yield across SplashDeferredShell mount before fading the splash away.
      setState(() {
        _shell = shell;
        _error = null;
        _retrying = false;
      });
      _usageAutoRefresh?.dispose();
      _usageAutoRefresh = ManagedProviderUsageAutoRefresh(
        usage: shell.managedProviderUsageCubit,
        providers: shell.managedProviderCubit,
      )..start();
      await yieldUiFrame();
      await yieldUiFrame();
      await yieldUiFrame();
      await yieldUiFrame();
      if (!mounted) return;
      await completeBootSplashTransition();
      // Cache warm-ups yield to the first painted frame: on SSH homes the
      // reads are decrypted on the UI isolate, so starting them alongside
      // bootstrap would stretch the splash for every extra byte.
      unawaited(shell.warmStartupCaches());
    } on Object catch (error, stackTrace) {
      await _teardownConnect(builtShell);
      await builtShell?.managedProviderControlPlane.close();
      await builtShell?.homeConnectionCubit.close();
      // The failed shell is discarded: stop its catalog mutation bus before a
      // bootstrap retry constructs a new one, so the app-lifetime dispatcher
      // no longer relays mutations into the dead shell's cubits (same seam as
      // the buildAppShell failure path). The presence cubit is closed for the
      // same reason: it subscribes to the app-lifetime presence projection.
      await builtShell?.memberPresenceCubit.close();
      builtShell?.cursorUsageApiClient.close();
      await builtShell?.catalogRuntime?.bus.close();
      await _eventTransportController.apply(EventTransportRole.none);
      appLogger.e(
        '[boot] buildAppShell failed',
        error: error,
        stackTrace: stackTrace,
      );
      if (!mounted) return;
      await completeBootSplashTransition();
      if (!mounted) return;
      setState(() {
        _error = error;
        _retrying = false;
      });
    }
  }

  Future<void> _retryBootstrap() async {
    if (_retrying) return;
    setState(() => _retrying = true);
    await _start();
  }

  Future<void> _chooseWorkEnvironmentAndRetry() async {
    if (_retrying) return;
    setState(() => _retrying = true);
    await HomeTargetStore(widget.preferences).save(RuntimeTarget.localId);
    await _start();
  }

  Future<void> _switchToNativeStorageAndRetry() async {
    if (_retrying) return;
    setState(() => _retrying = true);
    // Home target failed to install (e.g. WSL unavailable) — fall back to the
    // local device as home and retry bootstrap.
    await HomeTargetStore(widget.preferences).save(RuntimeTarget.localId);
    await _start();
  }

  @override
  void dispose() {
    _usageAutoRefresh?.dispose();
    final shell = _shell;
    if (shell != null) {
      shell.cancelShellSubscriptions();
      final lifecycleHandler = shell.sessionLifecycleHandler;
      if (lifecycleHandler != null) {
        _eventDispatcher.unregister(lifecycleHandler);
      }
      unawaited(shell.homeVaultScope.dispose());
      shell.homeInvalidationService.stop();
      unawaited(_teardownConnect(shell));
      unawaited(shell.managedProviderControlPlane.close());
      unawaited(shell.sessionUsageCubit.close());
      unawaited(shell.homeConnectionCubit.close());
      shell.sessionActivitySource.dispose();
      unawaited(shell.sessionProtocolController.applyNone());
      unawaited(shell.sessionAuthority.dispose());
      unawaited(shell.sessionRemoteActivityCubit.close());
      shell.cursorUsageApiClient.close();
    }
    // Drain queued events; dispose() is synchronous, so stop() is
    // fire-and-forget like the cubit closes above.
    //
    // Ordering (LOAD-BEARING): the projection must close only AFTER the
    // dispatcher has stopped delivering. We cannot `await` in a sync dispose,
    // so we chain instead: stop()'s future completes once the consume loop has
    // drained the queue and exited, so the continuation — and the projection
    // close — runs strictly after the last delivery. The projection also
    // guards its own broadcast add (`if (!_changes.isClosed)`), so even a late
    // event would be dropped rather than throw; the chain is belt-and-braces.
    unawaited(_stopEventTransport());
    unawaited(_eventDispatcher.stop().then((_) => _presenceProjection.close()));
    super.dispose();
  }

  bool get _canFallbackToNativeStorage {
    if (!Platform.isWindows || _error == null) return false;
    return runtimeKindOfId(HomeTargetStore(widget.preferences).load()) ==
        RuntimeKind.wsl;
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return MaterialApp(
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: appLocalizationsSupportedLocales,
        home: BootstrapStartupErrorPage(
          error: _error!,
          showChooseWorkEnvironment: Platform.isAndroid,
          showNativeStorageFallback: _canFallbackToNativeStorage,
          retrying: _retrying,
          onRetry: _retryBootstrap,
          onChooseWorkEnvironment: _chooseWorkEnvironmentAndRetry,
          onNativeStorageFallback: _switchToNativeStorageAndRetry,
        ),
      );
    }
    final shell = _shell;
    if (shell == null) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: appLocalizationsSupportedLocales,
        home: const AppBootstrapLoadingPage(),
      );
    }
    return MultiBlocProvider(
      providers: [
        // Above the router so StartupGate / RemoteConnectionsPage can read it.
        // `buildAppShell` created the cubit before this subtree was built, so
        // `.value` (no ownership transfer) is correct.
        BlocProvider<HomeConnectionCubit>.value(
          value: shell.homeConnectionCubit,
        ),
        BlocProvider.value(value: shell.managedProviderCubit),
        BlocProvider.value(value: shell.managedProviderUsageCubit),
        BlocProvider.value(value: shell.sessionUsageCubit),
        if (shell.connectCubit != null)
          BlocProvider<ConnectCubit>.value(value: shell.connectCubit!),
      ],
      child: widget.childBuilder(shell, _stopEventTransport),
    );
  }
}

/// Tears down the Connect stack: the QR-session cubit, both SSH backends,
/// and the shared paired-device registry. Safe to call with a null shell
/// (Android) and on partially-built shells.
Future<void> _teardownConnect(AppShell? shell) async {
  await shell?.connectCubit?.close();
  await shell?.embeddedSshServer?.stop();
  await shell?.systemSshdBackend?.stop();
  shell?.connectDeviceStore?.dispose();
}
