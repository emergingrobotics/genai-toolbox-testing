# Using Claude Code with MCP Toolbox

This guide explains how to connect Claude Code to the Google MCP Toolbox server to interact with your database.

## Prerequisites

1. The MCP Toolbox server is running (see main README.md)
2. Claude Code is installed
3. Server is accessible at `http://localhost:5001`

## Quick Setup

Add the MCP server to Claude Code:

```bash
claude mcp add --transport sse toolbox-db http://localhost:5001/mcp/sse
```

That's it! The database tools are now available in Claude Code.

**Note:** The Google MCP Toolbox uses SSE (Server-Sent Events) transport and exposes the endpoint at `/mcp/sse`.

## Verify Connection

Check configured MCP servers:

```bash
claude mcp list
```

## Manual Configuration

If you prefer manual configuration, add to `.mcp.json` in your project root:

```json
{
  "mcp": {
    "servers": {
      "toolbox-db": {
        "type": "sse",
        "url": "http://localhost:5001/mcp/sse"
      }
    }
  }
}
```

### Configuration File Locations

| Scope | Location | Use Case |
|-------|----------|----------|
| Project | `.mcp.json` | Share with team via git |
| User | `~/.claude.json` | Personal, all projects |

### Environment Variable Support

Use environment variables for flexible configuration:

```json
{
  "mcp": {
    "servers": {
      "toolbox-db": {
        "type": "sse",
        "url": "${TOOLBOX_URL:-http://localhost:5001/mcp/sse}"
      }
    }
  }
}
```

## Using the Tools

Once connected, Claude Code has access to these tools:

- **list-tables** - List all tables in the database
- **describe-table** - Get column details for a table
- **run-query** - Execute SQL queries
- **count-rows** - Count rows in a table

### Example Prompts

```
List all tables in the database
```

```
Describe the structure of the Users table
```

```
How many rows are in the Orders table?
```

```
Run a query to get the top 10 customers by order count
```

## Troubleshooting

### Connection Refused

Ensure the MCP Toolbox server is running:

```bash
./server/scripts/run.sh
```

### Timeout Errors

Increase timeout for slow queries:

```bash
export MCP_TOOL_TIMEOUT=60000  # 60 seconds
claude
```

### Server Not Appearing

Check if the server is enabled:

```bash
claude mcp list
```

If disabled, enable it in your settings or re-add:

```bash
claude mcp remove toolbox-db
claude mcp add --transport sse toolbox-db http://localhost:5001/mcp/sse
```

### Authentication Issues

For remote/production servers requiring authentication:

1. Use the `/mcp` command within Claude Code
2. Follow the OAuth prompts if required

## Configuration Precedence

Settings are applied in this order (highest to lowest):

1. Enterprise managed settings
2. Command-line arguments
3. Local configuration
4. Project configuration (`.mcp.json`)
5. User configuration (`~/.claude.json`)

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `MCP_TIMEOUT` | Server startup timeout (ms) | 10000 |
| `MCP_TOOL_TIMEOUT` | Tool execution timeout (ms) | 30000 |
| `MAX_MCP_OUTPUT_TOKENS` | Max response tokens | 25000 |

## Removing the Server

```bash
claude mcp remove toolbox-db
```

## Additional Resources

- [Claude Code MCP Documentation](https://docs.anthropic.com/en/docs/claude-code/mcp)
- [Google MCP Toolbox Documentation](https://googleapis.github.io/genai-toolbox/)
