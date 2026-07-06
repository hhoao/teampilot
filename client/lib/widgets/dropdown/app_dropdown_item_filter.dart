/// Default case-insensitive substring filter for searchable dropdowns.
bool appDropdownItemMatchesQuery({
  required String query,
  required String searchText,
  bool Function(String searchText, String normalizedQuery)? predicate,
}) {
  final normalizedQuery = query.trim().toLowerCase();
  if (normalizedQuery.isEmpty) return true;
  if (predicate != null) {
    return predicate(searchText, normalizedQuery);
  }
  return searchText.toLowerCase().contains(normalizedQuery);
}
