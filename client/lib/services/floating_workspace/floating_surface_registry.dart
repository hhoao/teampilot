import 'floating_surface.dart';

class FloatingSurfaceRegistry {
  FloatingSurfaceRegistry(List<FloatingSurface> surfaces)
    : _byId = {for (final s in surfaces) s.id: s};

  factory FloatingSurfaceRegistry.withDefaults({
    required FloatingSurface file,
    required FloatingSurface terminal,
    FloatingSurface? diff,
    FloatingSurface? run,
  }) => FloatingSurfaceRegistry([
    terminal,
    file,
    if (diff != null) diff,
    if (run != null) run,
  ]);

  final Map<String, FloatingSurface> _byId;

  FloatingSurface? operator [](String id) => _byId[id];

  // Order follows registration/insertion order; withDefaults registers terminal then file.
  List<FloatingEmptyAction> get emptyActions => [
    for (final s in _byId.values)
      if (s.emptyAction != null) s.emptyAction!,
  ];
}
