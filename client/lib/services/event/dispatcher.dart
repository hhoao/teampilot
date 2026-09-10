/// YARN-style central event dispatch interfaces.
///
/// Port of org.apache.hadoop.yarn.event {Event, EventHandler, Dispatcher}.
/// Vocabulary is per-family: each event family defines its own sealed class
/// + kind enum (like YARN's per-domain *EventType enums); the dispatcher is
/// generic over families and knows no concrete vocabulary.
library;

/// An event flowing through a [Dispatcher]. `K` is the family's kind enum.
abstract interface class DispatcherEvent<K extends Enum> {
  /// The family kind of this event.
  ///
  /// Named [eventKind] (not `kind`, YARN's `getType()`) because event
  /// payloads commonly carry their own domain-typed `kind` field, which
  /// would collide with the interface getter (e.g.
  /// `CatalogMutationEvent.kind` is the catalog domain kind, a String).
  K get eventKind;

  /// When the event occurred at its source (YARN AbstractEvent timestamp).
  DateTime get timestamp;
}

/// A consumer registered for an event family (YARN EventHandler).
abstract interface class EventHandler<T extends DispatcherEvent> {
  void handle(T event);
}

/// The central dispatcher (YARN Dispatcher). Publishing via [dispatch] is
/// fire-and-forget; consumers register per family.
abstract interface class Dispatcher {
  /// Enqueue [event]; returns immediately, never blocks (YARN
  /// getEventHandler().handle()).
  void dispatch(DispatcherEvent event);

  /// Register [handler] for the family identified at runtime by [kindType]
  /// (the family's kind enum [Type]). `K` is for static typing only; the
  /// runtime family identity is the [kindType] argument. If a handler is
  /// already registered for the family, both are invoked (YARN
  /// MultiListenerHandler).
  void registerFamily<K extends Enum>(Type kindType, EventHandler handler);

  /// Remove [handler] from every family it was registered for.
  void unregister(EventHandler handler);
}
