# Bug Report: MSSQL mssql-sql kind template syntax broken in v0.24.0

**Repository:** googleapis/genai-toolbox
**Component:** MSSQL source
**Version:** v0.24.0

---

## Summary

The `mssql-sql` tool kind with Go template syntax (`{{.query}}`) does not work correctly in v0.24.0. Queries return empty results or errors instead of executing the parameterized SQL.

## Steps to Reproduce

1. Create a `tools.yaml` with a templated MSSQL tool:

```yaml
sources:
  baseline-mssql:
    kind: mssql
    host: ${SQLCMDSERVER}
    port: 1433
    database: ${SQLCMDDBNAME}
    user: ${SQLCMDUSER}
    password: ${SQLCMDPASSWORD}

tools:
  run-query:
    kind: mssql-sql
    source: baseline-mssql
    description: Run a SQL query
    parameters:
      - name: query
        type: string
        description: The SQL query to execute
    statement: "{{.query}}"
```

2. Start the toolbox server:
```bash
podman run -p 5001:5000 \
  -e SQLCMDSERVER -e SQLCMDUSER -e SQLCMDPASSWORD -e SQLCMDDBNAME \
  -v ./tools.yaml:/app/tools.yaml:Z \
  us-central1-docker.pkg.dev/database-toolbox/toolbox/toolbox:0.24.0 \
  --tools-file "/app/tools.yaml" \
  --address "0.0.0.0"
```

3. Invoke the tool:
```bash
curl -X POST http://127.0.0.1:5001/api/tool/run-query/invoke \
  -H "Content-Type: application/json" \
  -d '{"query": "SELECT TOP 5 * FROM MyTable"}'
```

## Expected Behavior

The query should execute and return results from the database.

## Actual Behavior

The tool returns empty results or an error. The template variable `{{.query}}` is not being substituted with the parameter value.

## Workaround

Use `mssql-execute-sql` kind instead, which accepts raw SQL via the `sql` parameter:

```yaml
tools:
  run-query:
    kind: mssql-execute-sql
    source: baseline-mssql
    description: Run a SQL query
```

Invoke with:
```bash
curl -X POST http://127.0.0.1:5001/api/tool/run-query/invoke \
  -H "Content-Type: application/json" \
  -d '{"sql": "SELECT TOP 5 * FROM MyTable"}'
```

This works correctly.

## Environment

- **genai-toolbox version:** 0.24.0
- **Container runtime:** podman/docker
- **Host OS:** WSL2 (Ubuntu), macOS
- **Database:** MS SQL Server (AWS RDS)

## Additional Context

- The `list-tables` and `describe-table` tools with fixed `mssql-sql` statements work fine
- Only parameterized templates with `{{.variable}}` syntax fail
- This may be related to Go template parsing or parameter injection

---

**File this issue at:** https://github.com/googleapis/genai-toolbox/issues/new
