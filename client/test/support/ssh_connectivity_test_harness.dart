import 'dart:async';

import 'package:teampilot/services/ssh/ssh_home_connectivity_state.dart';

/// Controllable [SshConnectivitySource] for cubit/widget tests. Emit a state
/// to drive every projection without building a real SSH factory.
final class TestSshConnectivity implements SshConnectivitySource {
  final _controller = StreamController<SshHomeConnectivityState>.broadcast();
  final _states = <String, SshHomeConnectivityState>{};

  @override
  Stream<SshHomeConnectivityState> get changes => _controller.stream;

  @override
  SshHomeConnectivityState stateFor(String profileId) =>
      _states[profileId] ?? SshHomeConnectivityState(profileId: profileId);

  void emit(SshHomeConnectivityState state) {
    _states[state.profileId] = state;
    if (!_controller.isClosed) _controller.add(state);
  }

  Future<void> dispose() => _controller.close();
}
