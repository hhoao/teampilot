import '../../registry/capabilities/wait_before_stop_capability.dart';

final class CursorWaitBeforeStop implements WaitBeforeStopCapability {
  const CursorWaitBeforeStop();

  @override
  bool get defaultForceWaitBeforeStop => false;
}
