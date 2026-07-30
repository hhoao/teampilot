import 'package:teampilot/services/floating_workspace/floating_surface.dart';

class FloatingSurfaceRegistry {
  FloatingSurfaceRegistry(List<FloatingSurface> surfaces)
    : _byId = {for (final s in surfaces) s.id: s};

  factory FloatingSurfaceRegistry.withDefaults({
    required FloatingSurface file,
    required FloatingSurface terminal,
  }) => FloatingSurfaceRegistry([terminal, file]);

  final Map<String, FloatingSurface> _byId;

  FloatingSurface? operator [](String id) => _byId[id];

  List<FloatingEmptyAction> get emptyActions => [
    for (final s in _byId.values)
      if (s.emptyAction != null) s.emptyAction!,
  ];
}
