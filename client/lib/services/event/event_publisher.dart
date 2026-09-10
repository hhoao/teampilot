import 'dispatcher.dart';
import 'session_lifecycle_event.dart';

/// Injection seam for the central [Dispatcher].
///
/// The app attaches the real dispatcher once from app_shell; before attach
/// (tests, early startup) all publishes are no-ops, so event sources stay
/// construction-free — no constructor threading of a dispatcher through the
/// cubit/pipeline graph.
///
/// This is an injection bridge only and carries no business state.
///
/// App code publishes via [instance]; tests construct isolated publishers so
/// they never touch the app-lifecycle singleton.
class EventPublisher {
  EventPublisher();

  static final EventPublisher instance = EventPublisher();

  Dispatcher? _dispatcher;

  /// The attached dispatcher, or null before [attach] / after a stop.
  ///
  /// Consumers that need dispatch guarantees (e.g. awaiting drain) read this;
  /// publishers themselves never should.
  Dispatcher? get attachedDispatcher => _dispatcher;

  void attach(Dispatcher d) => _dispatcher = d;

  /// Fire-and-forget publish; a no-op while no dispatcher is attached.
  void dispatchSessionLifecycle(SessionLifecycleEvent event) =>
      _dispatcher?.dispatch(event);
}
