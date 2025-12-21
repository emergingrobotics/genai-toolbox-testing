# Google MCP Toolbox for Databases Testing

This project tests [Google MCP Toolbox for Databases](https://googleapis.github.io/genai-toolbox/), running it in a container to interact with MS SQL Server databases.

## Project Structure

```
.
├── configs/
│   └── tools.yaml       # Toolbox configuration (sources, tools, toolsets)
├── server/
│   ├── scripts/
│   │   ├── pull.sh      # Pull the container image
│   │   └── run.sh       # Run the toolbox server
│   └── notes.md         # Container setup notes
├── genai-toolbox/       # Cloned source (for reference)
├── .envrc               # Environment variables (not in git)
└── envrc                # Template for .envrc
```

## Setup

### 1. Configure Environment Variables

Copy the template and fill in your credentials:

```bash
cp envrc .envrc
```

Edit `.envrc` with your SQL Server connection details:

```bash
export SQLCMDSERVER="your-sql-server-hostname"
export SQLCMDUSER="your-username"
export SQLCMDPASSWORD="your-password"
export SQLCMDDBNAME="your-database"
export SQLCMDENCRYPT="no"
```

### 2. Pull the Container Image

```bash
./server/scripts/pull.sh
```

### 3. Run the Server

```bash
./server/scripts/run.sh
```

The server will be available at `http://localhost:5001`.

## Testing the Server

### Verify the server is running

```bash
curl http://127.0.0.1:5001/
# Expected: 🧰 Hello, World! 🧰
```

### List available tools

```bash
curl http://127.0.0.1:5001/api/toolset
```

### Invoke a tool

```bash
# List all tables
curl -X POST http://127.0.0.1:5001/api/tool/list-tables/invoke \
  -H "Content-Type: application/json" \
  -d '{}'

# Describe a specific table
curl -X POST http://127.0.0.1:5001/api/tool/describe-table/invoke \
  -H "Content-Type: application/json" \
  -d '{"table_name": "YourTableName"}'

# Count rows in a table
curl -X POST http://127.0.0.1:5001/api/tool/count-rows/invoke \
  -H "Content-Type: application/json" \
  -d '{"table_name": "YourTableName"}'

# Run a custom query
curl -X POST http://127.0.0.1:5001/api/tool/run-query/invoke \
  -H "Content-Type: application/json" \
  -d '{"query": "SELECT TOP 10 * FROM YourTableName"}'
```

## Connecting Claude Code

Add the MCP server to Claude Code:

```bash
claude mcp add --transport sse toolbox-db http://localhost:5001/mcp/sse
```

Verify the connection:

```bash
claude mcp list
```

For detailed configuration options, see [docs/using-claude-code.md](docs/using-claude-code.md).

## Available Tools

The default configuration provides these tools:

| Tool | Description |
|------|-------------|
| `list-tables` | List all user tables in the database |
| `describe-table` | Get column details for a specific table |
| `run-query` | Execute a SQL query |
| `count-rows` | Count rows in a specific table |

## Configuration

### Adding Custom Tools

Edit `configs/tools.yaml` to add custom tools. Example parameterized query:

```yaml
tools:
  search-customers:
    kind: mssql-sql
    source: baseline-mssql
    description: Search for customers by name
    parameters:
      - name: name
        type: string
        description: Customer name to search for
    statement: |
      SELECT TOP 100 *
      FROM Customers
      WHERE CustomerName LIKE '%' + @p1 + '%'
```

See the [MS SQL source documentation](https://googleapis.github.io/genai-toolbox/resources/sources/mssql/) for all available options.

## Connection Pooling

The toolbox uses Go's standard `database/sql` package with the `microsoft/go-mssqldb` driver. A single shared connection pool is created when the source is initialized, and all MCP sessions share this pool automatically.

### Default Pool Settings

The MSSQL source uses Go's default pool settings (no configuration needed):

| Setting | Default Value |
|---------|---------------|
| Max Open Connections | Unlimited |
| Max Idle Connections | 2 |
| Connection Max Lifetime | Unlimited |
| Connection Max Idle Time | Unlimited |

### Multiple Simultaneous Sessions

Multiple simultaneous sessions work out of the box. You don't need to configure anything special. Multiple Claude Code sessions (or any MCP clients) can connect simultaneously and the pool handles it automatically.

Each query acquires a connection from the pool and returns it when done. The pool creates new connections on-demand as needed.

### Pool Configuration

There is currently **no way to configure pool size** through the YAML config - it's not exposed by the toolbox. The MSSQL source relies on Go's defaults, unlike some other database sources in the toolbox:

| Database | Max Open | Max Idle |
|----------|----------|----------|
| MSSQL | Unlimited (default) | 2 (default) |
| ClickHouse | 25 | 5 |
| Firebird | 5 | 2 |
| Trino | 10 | 5 |
| SQLite | 1 | 1 |

For most development and light production use, the defaults are fine. For high-concurrency production workloads, be aware that unlimited connections could exhaust database resources.

## Production Deployment

### Restrict Allowed Origins

The development server allows all origins (`*`), which is insecure. In production, use the `--allowed-origins` flag:

```bash
podman run -p 5001:5000 \
  -e SQLCMDSERVER \
  -e SQLCMDUSER \
  -e SQLCMDPASSWORD \
  -e SQLCMDDBNAME \
  -v ./configs/tools.yaml:/app/tools.yaml:Z \
  us-central1-docker.pkg.dev/database-toolbox/toolbox/toolbox:0.24.0 \
  --tools-file "/app/tools.yaml" \
  --address "0.0.0.0" \
  --allowed-origins "https://your-app.example.com"
```

Multiple origins can be comma-separated:

```bash
--allowed-origins "https://app.example.com,https://admin.example.com"
```

### Other Security Considerations

- Use encrypted connections (`encrypt: true` in tools.yaml) for production databases
- Use a read-only database user when possible
- Prefer parameterized queries over arbitrary SQL execution
- Run the container with minimal privileges

## Troubleshooting

### Port 5000 in use (macOS)

On macOS, port 5000 is used by AirPlay Receiver. The run script uses port 5001 instead. Alternatively, disable AirPlay Receiver in System Settings → General → AirDrop & Handoff.

### SELinux volume mount issues

On SELinux-enabled systems (Fedora, RHEL, CentOS), the `:Z` suffix on volume mounts relabels content for container access. For shared volumes, use `:z` (lowercase) instead.

### Container version

To use a different version, edit the `VERSION` variable in the scripts or set it before running:

```bash
VERSION=0.25.0 ./server/scripts/run.sh
```
