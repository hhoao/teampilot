import 'trace_decoder.dart';

/// Filters timeline slices/events for analysis output.
class TraceFilters {
  const TraceFilters({
    this.namePattern,
    this.categories = const {},
    this.excludeEmbedder = false,
  });

  final String? namePattern;
  final Set<String> categories;
  final bool excludeEmbedder;

  bool get isActive =>
      excludeEmbedder ||
      categories.isNotEmpty ||
      (namePattern != null && namePattern!.isNotEmpty);

  bool matchesSlice(TraceSlice slice) {
    if (excludeEmbedder && _isEmbedder(slice)) return false;
    if (categories.isNotEmpty && !_categoryMatches(slice)) return false;
    if (namePattern != null &&
        namePattern!.isNotEmpty &&
        !slice.name.toLowerCase().contains(namePattern!.toLowerCase())) {
      return false;
    }
    return true;
  }

  bool matchesInstant(TraceInstant event) {
    if (excludeEmbedder && _isEmbedderInstant(event)) return false;
    if (categories.isNotEmpty && !_categoryMatchesInstant(event)) return false;
    if (namePattern != null &&
        namePattern!.isNotEmpty &&
        !event.name.toLowerCase().contains(namePattern!.toLowerCase())) {
      return false;
    }
    return true;
  }

  List<TraceSlice> applySlices(List<TraceSlice> slices) =>
      isActive ? slices.where(matchesSlice).toList() : slices;

  bool _isEmbedder(TraceSlice slice) =>
      slice.category == 'Embedder' || slice.trackLabel == 'Embedder';

  bool _isEmbedderInstant(TraceInstant event) =>
      event.category == 'Embedder' || event.track == 'Embedder';

  bool _categoryMatches(TraceSlice slice) {
    for (final category in categories) {
      if (slice.category == category || slice.trackLabel == category) {
        return true;
      }
    }
    return false;
  }

  bool _categoryMatchesInstant(TraceInstant event) {
    for (final category in categories) {
      if (event.category == category || event.track == category) {
        return true;
      }
    }
    return false;
  }
}
