const mcpInstalledRoute = '/mcp/installed';

String mcpAddRoute() => '/mcp/add';

String mcpEditRoute(String serverId) =>
    '/mcp/edit/${Uri.encodeComponent(serverId)}';

bool mcpPathIsForm(String path) =>
    path == mcpAddRoute() || path.startsWith('/mcp/edit/');
