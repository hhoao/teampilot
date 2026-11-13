import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../cubits/session/acp/acp_chat_runtime_cubit.dart';
import '../../services/acp/acp_client_extensions.dart';
import '../../services/acp/acp_session.dart';
import '../../services/cli/registry/capabilities/native_command_capability.dart';

/// The four ACP bits the compose section renders.
///
/// Keeping them in one value object lets an inherited scope notify compose
/// without rebuilding the whole chat subtree on every streaming token.
@immutable
final class AcpRuntimeUiState {
  const AcpRuntimeUiState({
    required this.pendingClient,
    required this.inTurn,
    required this.modelState,
    required this.availableCommands,
  });

  final AcpPendingClientRequest? pendingClient;
  final bool inTurn;
  final AcpModelState? modelState;
  final List<NativeCommand> availableCommands;

  static AcpRuntimeUiState of(AcpChatRuntimeState state) => AcpRuntimeUiState(
    pendingClient: state.pendingClient,
    inTurn: state.inTurn,
    modelState: state.modelState,
    availableCommands: state.availableCommands,
  );

  @override
  bool operator ==(Object other) =>
      other is AcpRuntimeUiState &&
      other.pendingClient == pendingClient &&
      other.inTurn == inTurn &&
      other.modelState == modelState &&
      other.availableCommands == availableCommands;

  @override
  int get hashCode =>
      Object.hash(pendingClient, inTurn, modelState, availableCommands);
}

/// Always-present ACP runtime scope.
///
/// The provider was previously a `BlocProvider` that swapped between a bare
/// child and a fake idle cubit. The fake cubit violated LSP/ISP and existed
/// only to keep the widget type stable. This scope keeps the same type while
/// exposing a nullable runtime and a small UI-state snapshot.
class AcpRuntimeScope extends StatefulWidget {
  const AcpRuntimeScope({
    required this.runtime,
    required this.child,
    super.key,
  });

  final AcpChatRuntimeCubit? runtime;
  final Widget child;

  static AcpRuntimeUiState? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_AcpRuntimeUiScope>()?.value;

  @override
  State<AcpRuntimeScope> createState() => _AcpRuntimeScopeState();
}

class _AcpRuntimeScopeState extends State<AcpRuntimeScope> {
  StreamSubscription<AcpChatRuntimeState>? _sub;
  AcpRuntimeUiState? _ui;

  @override
  void initState() {
    super.initState();
    _bind();
  }

  @override
  void didUpdateWidget(covariant AcpRuntimeScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.runtime, widget.runtime)) _bind();
  }

  void _bind() {
    unawaited(_sub?.cancel());
    _sub = null;
    final runtime = widget.runtime;
    _ui = runtime == null ? null : AcpRuntimeUiState.of(runtime.state);
    if (runtime == null) return;
    _sub = runtime.stream.listen((state) {
      final next = AcpRuntimeUiState.of(state);
      if (!mounted || next == _ui) return;
      setState(() => _ui = next);
    });
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _AcpRuntimeUiScope(value: _ui, child: widget.child);
}

class _AcpRuntimeUiScope extends InheritedWidget {
  const _AcpRuntimeUiScope({required this.value, required super.child});

  final AcpRuntimeUiState? value;

  @override
  bool updateShouldNotify(_AcpRuntimeUiScope oldWidget) =>
      oldWidget.value != value;
}
