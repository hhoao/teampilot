import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/mcp/mcp_probe_headers.dart';
import 'package:teampilot/services/mcp/smithery_mcp_auth.dart';

void main() {
  test('copies catalog headers', () {
    final headers = buildMcpProbeHeaders(
      const McpProbeHeaderInput(
        spec: {
          'type': 'http',
          'url': 'https://example.com/mcp',
          'headers': {'X-Custom': 'a'},
        },
      ),
    );
    expect(headers['X-Custom'], 'a');
  });

  test('adds oauth bearer when access token present', () {
    final headers = buildMcpProbeHeaders(
      const McpProbeHeaderInput(
        spec: {'type': 'http', 'url': 'https://example.com/mcp'},
        oauthAccessToken: 'tok_123',
      ),
    );
    expect(headers[SmitheryMcpAuth.authorizationHeader], 'Bearer tok_123');
  });

  test('smithery catalog bearer wins over missing oauth', () {
    final spec = {'type': 'http', 'url': 'https://server.smithery.ai/@org/srv'};
    final headers = buildMcpProbeHeaders(
      McpProbeHeaderInput(spec: spec, smitheryApiToken: 'sm_1'),
    );
    expect(headers[SmitheryMcpAuth.authorizationHeader], 'Bearer sm_1');
  });

  test('env bearer fills Authorization when var is set', () {
    final headers = buildMcpProbeHeaders(
      McpProbeHeaderInput(
        spec: {
          'type': 'http',
          'url': 'https://example.com/mcp',
          'bearer_token_env_var': 'TEAMPILOT_MCP_BEARER_X',
        },
        readEnv: (name) => name == 'TEAMPILOT_MCP_BEARER_X' ? 'envtok' : null,
      ),
    );
    expect(headers[SmitheryMcpAuth.authorizationHeader], 'Bearer envtok');
  });

  test('oauth-capable without token reports needsAuthBeforeConnect', () {
    final decision = mcpProbeAuthDecision(
      const McpProbeHeaderInput(
        spec: {'type': 'http', 'url': 'https://example.com/mcp'},
        oauthApplicable: true,
        oauthAccessToken: null,
      ),
    );
    expect(decision, McpProbeAuthDecision.needsAuth);
  });

  test(
    'catalog Authorization proceeds when oauth applicable without token',
    () {
      final decision = mcpProbeAuthDecision(
        const McpProbeHeaderInput(
          spec: {
            'type': 'http',
            'url': 'https://example.com/mcp',
            'headers': {'Authorization': 'Bearer catalog_tok'},
          },
          oauthApplicable: true,
        ),
      );
      expect(decision, McpProbeAuthDecision.proceed);
    },
  );

  test('env bearer proceeds when oauth applicable without token', () {
    final decision = mcpProbeAuthDecision(
      McpProbeHeaderInput(
        spec: {
          'type': 'http',
          'url': 'https://example.com/mcp',
          'bearer_token_env_var': 'TEAMPILOT_MCP_BEARER_X',
        },
        oauthApplicable: true,
        readEnv: (name) => name == 'TEAMPILOT_MCP_BEARER_X' ? 'envtok' : null,
      ),
    );
    expect(decision, McpProbeAuthDecision.proceed);
  });

  test(
    'smithery catalog bearer proceeds when oauth applicable without token',
    () {
      final decision = mcpProbeAuthDecision(
        const McpProbeHeaderInput(
          spec: {'type': 'http', 'url': 'https://server.smithery.ai/@org/srv'},
          oauthApplicable: true,
          smitheryApiToken: 'sm_1',
        ),
      );
      expect(decision, McpProbeAuthDecision.proceed);
    },
  );
}
