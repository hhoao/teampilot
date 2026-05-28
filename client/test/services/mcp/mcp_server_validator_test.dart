import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/mcp/mcp_server_validator.dart';

void main() {
  final validator = McpServerValidator();

  test('stdio requires command', () {
    expect(
      validator.validateServer({'type': 'stdio'}),
      contains('command required for stdio'),
    );
  });

  test('http requires url', () {
    expect(
      validator.validateServer({'type': 'http'}),
      contains('url required for http'),
    );
  });

  test('valid stdio passes', () {
    expect(
      validator.validateServer({
        'type': 'stdio',
        'command': 'npx',
        'args': ['-y', 'pkg'],
      }),
      isEmpty,
    );
  });

  test('name must not contain spaces', () {
    expect(validator.validateName('my server'), isNotEmpty);
  });

  test('optional homepage must be valid URL when set', () {
    expect(
      validator.validate(
        const McpServerFields(
          id: 'x',
          name: 'pkg',
          server: {'type': 'stdio', 'command': 'npx'},
          homepage: 'not-a-url',
        ),
      ),
      contains('homepage must be a valid URL'),
    );
    expect(
      validator.validate(
        const McpServerFields(
          id: 'x',
          name: 'pkg',
          server: {'type': 'stdio', 'command': 'npx'},
          homepage: 'https://example.com',
        ),
      ),
      isEmpty,
    );
  });
}
