# Using Claude Code with MCP Toolbox

This guide explains how to connect Claude Code to the Google MCP Toolbox server to interact with your database.

## Prerequisites

1. The MCP Toolbox server is running (see main README.md)
2. Claude Code is installed
3. Server is accessible at `http://localhost:5001`

---

## Configuration

### Quick Setup

Add the MCP server to Claude Code:

```bash
claude mcp add --transport sse toolbox-db http://localhost:5001/mcp/sse
```

That's it! The database tools are now available in Claude Code.

**Note:** The Google MCP Toolbox uses SSE (Server-Sent Events) transport and exposes the endpoint at `/mcp/sse`.

### Verify Connection

Check configured MCP servers:

```bash
claude mcp list
```

### Manual Configuration

If you prefer manual configuration, add to `.mcp.json` in your project root:

```json
{
  "mcpServers": {
    "toolbox-db": {
      "type": "sse",
      "url": "http://localhost:5001/mcp/sse"
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
  "mcpServers": {
    "toolbox-db": {
      "type": "sse",
      "url": "${TOOLBOX_URL:-http://localhost:5001/mcp/sse}"
    }
  }
}
```

### Configuration Precedence

Settings are applied in this order (highest to lowest):

1. Enterprise managed settings
2. Command-line arguments
3. Local configuration
4. Project configuration (`.mcp.json`)
5. User configuration (`~/.claude.json`)

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `MCP_TIMEOUT` | Server startup timeout (ms) | 10000 |
| `MCP_TOOL_TIMEOUT` | Tool execution timeout (ms) | 30000 |
| `MAX_MCP_OUTPUT_TOKENS` | Max response tokens | 25000 |

### Removing the Server

```bash
claude mcp remove toolbox-db
```

---

## Single-Shot Command Lines

Use Claude Code for one-off database queries without entering interactive mode. This is useful for scripting, automation, or quick lookups.

### Basic Usage

```bash
claude -p "List all tables in the database"
```

The `-p` flag runs Claude with a single prompt and exits after completion.

### Examples

```bash
# List tables
claude -p "What tables are in the database?"

# Describe a table
claude -p "Describe the structure of the CarReport table"

# Count rows
claude -p "How many rows are in the TransactionReport table?"

# Run a query
claude -p "Show me the first 5 rows from CarReport"

# Complex query
claude -p "Find all transactions from the last 30 days grouped by category"
```

### Output Formats

```bash
# Default output (markdown-ish)
claude -p "List all tables"

# JSON output for parsing
claude -p "List all tables" --output-format json

# Stream output as it's generated
claude -p "List all tables" --stream
```

### Scripting Examples

```bash
# Save query results to a file
claude -p "Export all data from CarReport as CSV" > car_report.csv

# Use in a shell pipeline
claude -p "List table names only, one per line" | xargs -I {} claude -p "Count rows in {}"

# Conditional logic
TABLE_COUNT=$(claude -p "How many tables are in the database? Reply with just the number")
if [ "$TABLE_COUNT" -gt 10 ]; then
    echo "Large database detected"
fi
```

### Environment Variables for Single-Shot

```bash
# Increase timeout for slow queries
MCP_TOOL_TIMEOUT=120000 claude -p "Run a complex aggregation query"

# Use a different model
claude -p "Analyze the database schema" --model claude-sonnet-4-5-20250514
```

---

## Interactive (Live) Mode

Interactive mode provides a conversational interface where you can have back-and-forth discussions with Claude about your database.

### Starting Interactive Mode

```bash
# Start Claude Code in the current directory
claude

# Start with a specific directory
claude /path/to/project
```

### Available Tools

Once connected, Claude Code has access to these tools:

- **list-tables** - List all tables in the database
- **describe-table** - Get column details for a table
- **run-query** - Execute SQL queries
- **count-rows** - Count rows in a table

### Example Session

```
$ claude

> List all tables in the database

I'll query the database for you.
[Executing tool: list-tables]

The database contains the following tables:
1. CarReport (schema: dbo)
2. TransactionReport (schema: dbo)

> Describe the CarReport table

[Executing tool: describe-table]

The CarReport table has the following columns:
- id (int, NOT NULL)
- make (varchar(50))
- model (varchar(50))
- year (int)
- created_at (datetime)

> How many cars are from 2023?

[Executing tool: run-query]

There are 847 cars from 2023 in the database.

> quit
```

### Interactive Commands

While in interactive mode, you can use these commands:

| Command | Description |
|---------|-------------|
| `/help` | Show available commands |
| `/mcp` | List connected MCP servers and tools |
| `/clear` | Clear conversation history |
| `/compact` | Compact conversation to save context |
| `quit` or `exit` | Exit interactive mode |

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

```
Write a SQL query to find duplicate records in the Customers table
```

```
Analyze the schema and suggest indexes for better performance
```

### Multi-Turn Conversations

Interactive mode maintains context across messages:

```
> Show me the CarReport schema

[describes the table]

> Now count the rows

[knows you mean CarReport from context]

> Filter to only cars made by Toyota

[builds on previous query context]
```

---

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

1. Use the basic auth proxy (see `../basic-auth/README.md`)
2. Include credentials in the URL:
   ```bash
   claude mcp add --transport sse toolbox-db http://user:pass@localhost:8080/mcp/sse
   ```

### Tools Not Available

If Claude doesn't seem to have access to the database tools:

1. Check the MCP connection:
   ```bash
   claude mcp list
   ```

2. Verify the server is responding:
   ```bash
   curl http://localhost:5001/api/toolset
   ```

3. Restart Claude Code after adding the MCP server

---

## Additional Resources

- [Claude Code MCP Documentation](https://docs.anthropic.com/en/docs/claude-code/mcp)
- [Google MCP Toolbox Documentation](https://googleapis.github.io/genai-toolbox/)
