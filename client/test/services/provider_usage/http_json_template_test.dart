import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/provider_usage/http_json_template.dart';

void main() {
  test('empty accountId drops colon separators', () {
    expect(
      expandHttpJsonTemplate(
        '{accountId}::{accessToken}',
        {'accessToken': 'tok'},
      ),
      'tok',
    );
  });

  test('jwt.sub uses the segment after the last pipe', () {
    final payload = base64Url
        .encode(utf8.encode('{"sub":"github|user_01ABC"}'))
        .replaceAll('=', '');
    final jwt = 'eyJhbGciOiJub25lIn0.$payload.sig';
    expect(
      expandHttpJsonTemplate('{jwt.sub}', {'accessToken': jwt}),
      'user_01ABC',
    );
  });

  test('fillAccountIdFromJwt writes accountId when missing', () {
    final payload = base64Url
        .encode(utf8.encode('{"sub":"user_01ABC"}'))
        .replaceAll('=', '');
    final jwt = 'eyJhbGciOiJub25lIn0.$payload.sig';
    final filled = fillAccountIdFromJwt({'accessToken': jwt});
    expect(filled['accountId'], 'user_01ABC');
  });

  test('filled accountId and accessToken keep double colon separator', () {
    expect(
      expandHttpJsonTemplate(
        '{accountId}::{accessToken}',
        {'accountId': 'user', 'accessToken': 'tok'},
      ),
      'user::tok',
    );
  });

  test('WorkosCursorSessionToken keeps double colon when both values present', () {
    expect(
      expandHttpJsonTemplate(
        'WorkosCursorSessionToken={accountId}::{accessToken}',
        {'accountId': 'user', 'accessToken': 'tok'},
      ),
      'WorkosCursorSessionToken=user::tok',
    );
  });

  test('WorkosCursorSessionToken drops empty accountId colons after equals', () {
    expect(
      expandHttpJsonTemplate(
        'WorkosCursorSessionToken={accountId}::{accessToken}',
        {'accessToken': 'tok'},
      ),
      'WorkosCursorSessionToken=tok',
    );
  });
}
