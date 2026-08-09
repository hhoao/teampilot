import '../../registry/capabilities/wait_before_stop_capability.dart';

final class DefaultWaitBeforeStop implements WaitBeforeStopCapability {
  const DefaultWaitBeforeStop();

  @override
  bool get defaultForceWaitBeforeStop => true;
}
