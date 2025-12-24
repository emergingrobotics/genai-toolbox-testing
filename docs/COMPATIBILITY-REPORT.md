# GenAI Toolbox for Databases: Compatibility Report

**Date:** 2025-12-22
**Version Tested:** genai-toolbox v0.24.0
**Database:** MS SQL Server (AWS RDS)
**Transports Tested:** SSE (deprecated) and Streamable HTTP (recommended)
**Environment:** Docker on WSL2

---

## Executive Summary

Google's GenAI Toolbox for Databases v0.24.0 has a **critical bug** affecting MSSQL tools that use Go template syntax. Tools with fixed SQL statements work correctly, but parameterized tools using `{{.variable}}` templates fail completely.

| Category | Status |
|----------|--------|
| Basic connectivity | ✅ Working |
| Fixed SQL tools | ✅ Working |
| Parameterized tools (template syntax) | ❌ Broken |
| Claude CLI integration | ✅ Working (for functional tools) |

---

## Test Results

### Tool-by-Tool Results

| Tool | Kind | Template Syntax | curl Test | Claude CLI | Status |
|------|------|-----------------|-----------|------------|--------|
| list-tables | mssql-sql | None (fixed statement) | ✅ Pass | ✅ Pass | Working |
| describe-table | mssql-sql | `@p1` (SQL param) | ✅ Pass | ✅ Pass | Working |
| run-query | mssql-sql | `{{.query}}` | ❌ Fail | ❌ Fail | **BROKEN** |
| count-rows | mssql-sql | `{{.table_name}}` | ❌ Fail | ❌ Fail | **BROKEN** |

### Error Details

**Failed tools return:**
```json
{
  "status": "Bad Request",
  "error": "error while invoking tool: unable to execute query: mssql: Incorrect syntax near '<'."
}
```

**Root Cause:** Go template syntax (`{{.variable}}`) is NOT being rendered. The literal template string is passed to SQL Server, which interprets the curly braces and dots as invalid SQL syntax.

---

## Configuration Comparison

### Upstream (Broken)

```yaml
# configs/tools.yaml (main branch)
run-query:
  kind: mssql-sql
  source: baseline-mssql
  parameters:
    - name: query
      type: string
  statement: "{{.query}}"  # Template NOT rendered

count-rows:
  kind: mssql-sql
  parameters:
    - name: table_name
      type: string
  statement: |
    SELECT COUNT(*) as row_count FROM {{.table_name}}  # Template NOT rendered
```

### Fixed (Working)

```yaml
# configs/tools.yaml (docker-wsl branch)
run-query:
  kind: mssql-execute-sql  # Different kind - takes raw SQL
  source: baseline-mssql
  # No statement - SQL passed via 'sql' parameter

# count-rows removed - no workaround available
```

---

## Workarounds

### For run-query

Use `mssql-execute-sql` kind instead of `mssql-sql`:

```yaml
run-query:
  kind: mssql-execute-sql
  source: baseline-mssql
  description: Run a read-only SQL query against the database
```

Invoke with `sql` parameter:
```bash
curl -X POST http://localhost:5001/api/tool/run-query/invoke \
  -H "Content-Type: application/json" \
  -d '{"sql": "SELECT TOP 5 * FROM CarReport"}'
```

### For count-rows

**No workaround available.** The `mssql-execute-sql` kind doesn't support parameterized table names for safety reasons.

Options:
1. Remove the tool
2. Create separate count tools per table (not scalable)
3. Wait for upstream fix

---

## Claude CLI Integration

### Working Commands

```bash
# List tables
claude -p "List all tables in the database" --dangerously-skip-permissions

# Describe table
claude -p "Describe the CarReport table structure" --dangerously-skip-permissions
```

### Failing Commands

```bash
# Run custom query - FAILS with template error
claude -p "Run a query to get top 5 rows from CarReport" --dangerously-skip-permissions
```

---

## Transport Validation

### SSE Transport (Deprecated)

| Tool | curl | Claude CLI | Status |
|------|------|------------|--------|
| list-tables | ✅ Pass | ✅ Pass | Working |
| describe-table | ✅ Pass | ✅ Pass | Working |
| run-query (mssql-execute-sql) | ✅ Pass | ✅ Pass | Working |

**Endpoint:** `http://localhost:5001/mcp/sse`
**MCP Spec:** 2024-11-05 (DEPRECATED)

### Streamable HTTP Transport (Recommended)

**Tested:** 2025-12-22

| Tool | curl | Claude CLI | Status |
|------|------|------------|--------|
| list-tables | ✅ Pass | ✅ Pass | Working |
| describe-table | ✅ Pass | ✅ Pass | Working |
| run-query (mssql-execute-sql) | ✅ Pass | ✅ Pass | Working |

**Endpoint:** `http://localhost:5001/mcp`
**MCP Spec:** 2025-03-26 (RECOMMENDED)

### Transport Comparison

| Feature | SSE | Streamable HTTP |
|---------|-----|-----------------|
| Endpoint | `/mcp/sse` | `/mcp` |
| MCP Spec | 2024-11-05 | 2025-03-26 |
| Status | Deprecated | Recommended |
| Claude CLI | `--transport sse` | `--transport http` |
| All tools work | ✅ | ✅ |

### Configuration Examples

**SSE (deprecated):**
```bash
claude mcp add --transport sse toolbox-db http://localhost:5001/mcp/sse
```

**Streamable HTTP (recommended):**
```bash
claude mcp add --transport http toolbox-db http://localhost:5001/mcp
```

### JSON-RPC via Streamable HTTP

```bash
# List tools
curl -X POST http://localhost:5001/mcp \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"tools/list","id":1}'

# Call tool
curl -X POST http://localhost:5001/mcp \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"tools/call","id":2,"params":{"name":"list-tables","arguments":{}}}'
```

---

## Recommendations

### Immediate (Sprint 4)

1. **Use docker-wsl branch** with `mssql-execute-sql` workaround
2. **Remove count-rows** until upstream fixes template syntax
3. **File bug report** at googleapis/genai-toolbox

### For Production

1. **Wait for v0.25.0** - Template syntax fix may be included
2. **Consider custom MCP server** if genai-toolbox remains broken
3. **Use parameterized queries** with `@p1` syntax for SQL injection safety

---

## Upstream Bug Report

See [ISSUE-MSSQL-TEMPLATE-SYNTAX.md](./ISSUE-MSSQL-TEMPLATE-SYNTAX.md) for bug report draft.

**Issue:** MSSQL mssql-sql kind template syntax broken in v0.24.0
**Reproduction:** Any tool with `{{.variable}}` in statement fails
**Workaround:** Use `mssql-execute-sql` kind

---

## Test Environment

```
Container: us-central1-docker.pkg.dev/database-toolbox/toolbox/toolbox:0.24.0
Server Version: 0.24.0+container.release.linux.amd64.f520b4e
Database: MS SQL Server on AWS RDS
Host: WSL2 (Ubuntu) with Docker
Claude CLI: Tested with both SSE and HTTP transports
```

---

## Appendix: Raw Test Output

### list-tables (PASS)
```json
{"result":"[{\"TABLE_NAME\":\"CarReport\",\"TABLE_SCHEMA\":\"dbo\"},{\"TABLE_NAME\":\"TransactionReport\",\"TABLE_SCHEMA\":\"dbo\"}]"}
```

### run-query (FAIL)
```json
{"status":"Bad Request","error":"error while invoking tool: unable to execute query: mssql: Incorrect syntax near '<'."}
```

---

**Report generated by Claude Code on 2025-12-22**
