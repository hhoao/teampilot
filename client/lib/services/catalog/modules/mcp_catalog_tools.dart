import '../catalog_kind.dart';

const mcpCatalogTools = <CatalogToolSpec>[
  CatalogToolSpec(
    name: 'search_mcp',
    description: 'Search the TeamPilot MCP catalog',
    inputSchema: {
      'type': 'object',
      'properties': {
        'query': {'type': 'string'},
      },
    },
    mutating: false,
  ),
  CatalogToolSpec(
    name: 'read_mcp',
    description:
        'Read an installed MCP server spec with env and header secrets redacted',
    inputSchema: {
      'type': 'object',
      'properties': {
        'id': {'type': 'string'},
      },
      'required': ['id'],
    },
    mutating: false,
  ),
  CatalogToolSpec(
    name: 'install_mcp',
    description: 'Install an MCP server from a catalog listing and bind it',
    inputSchema: {
      'type': 'object',
      'properties': {
        'id': {'type': 'string'},
        'key': {'type': 'string'},
      },
    },
    mutating: true,
  ),
  CatalogToolSpec(
    name: 'import_mcp',
    description: 'Import MCP servers from a .mcp.json or mcpServers JSON file',
    inputSchema: {
      'type': 'object',
      'properties': {
        'path': {'type': 'string'},
      },
      'required': ['path'],
    },
    mutating: true,
  ),
  CatalogToolSpec(
    name: 'create_mcp',
    description: 'Create a local MCP server spec (stdio or http) and bind it',
    inputSchema: {
      'type': 'object',
      'properties': {
        'name': {'type': 'string'},
        'command': {'type': 'string'},
        'args': {
          'type': 'array',
          'items': {'type': 'string'},
        },
        'url': {'type': 'string'},
        'type': {'type': 'string'},
      },
      'required': ['name'],
    },
    mutating: true,
  ),
  CatalogToolSpec(
    name: 'update_mcp',
    description: 'Update an installed MCP server spec',
    inputSchema: {
      'type': 'object',
      'properties': {
        'id': {'type': 'string'},
        'name': {'type': 'string'},
        'command': {'type': 'string'},
        'url': {'type': 'string'},
      },
      'required': ['id'],
    },
    mutating: true,
  ),
  CatalogToolSpec(
    name: 'unbind_mcp',
    description: 'Unbind an MCP server from this workspace without deleting',
    inputSchema: {
      'type': 'object',
      'properties': {
        'id': {'type': 'string'},
      },
      'required': ['id'],
    },
    mutating: true,
  ),
  CatalogToolSpec(
    name: 'delete_mcp',
    description: 'Delete an MCP server and unbind it from this workspace',
    inputSchema: {
      'type': 'object',
      'properties': {
        'id': {'type': 'string'},
      },
      'required': ['id'],
    },
    mutating: true,
  ),
];
