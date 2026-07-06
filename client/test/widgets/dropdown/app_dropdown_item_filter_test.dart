import 'package:flutter_test/flutter_test.dart';

import 'package:teampilot/widgets/dropdown/app_dropdown_item_filter.dart';

void main() {
  group('appDropdownItemMatchesQuery', () {
    test('matches empty query against any item', () {
      expect(
        appDropdownItemMatchesQuery(query: '  ', searchText: 'Alpha'),
        isTrue,
      );
    });

    test('matches case-insensitive substring', () {
      expect(
        appDropdownItemMatchesQuery(query: 'BeT', searchText: 'Beta Model'),
        isTrue,
      );
      expect(
        appDropdownItemMatchesQuery(query: 'zzz', searchText: 'Beta Model'),
        isFalse,
      );
    });

    test('uses custom predicate when provided', () {
      expect(
        appDropdownItemMatchesQuery(
          query: 'abc',
          searchText: 'ignored',
          predicate: (_, q) => q == 'abc',
        ),
        isTrue,
      );
    });
  });
}
