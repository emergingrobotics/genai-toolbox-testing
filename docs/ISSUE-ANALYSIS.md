# MSSQL Template Syntax Issue Analysis

**Date:** 2025-12-23
**Analyzed Version:** genai-toolbox v0.24.0

---

## Summary

When using the `mssql-sql` kind with Go template syntax like `{{.query}}` in the statement field, the template **is being parsed but renders incorrectly**, resulting in SQL Server receiving invalid syntax.

---

## Root Cause in the Code

The issue is in how templates are resolved in `/genai-toolbox/internal/util/parameters/parameters.go:197-219`:

```go
func ResolveTemplateParams(templateParameters []ParameterConfig, statement string, paramsMap map[string]any) (string, error) {
    templateParamsMap, err := GetParams(templateParameters, paramsMap)  // Gets ONLY templateParameters
    ...
    t, err := template.New("query").Funcs(funcMap).Parse(statement)    // Parses statement as template
    ...
    err = t.Execute(&result, templateParamsMap)                         // Executes with ONLY templateParamsMap
    return result.String(), nil
}
```

**The critical distinction:** The toolbox has TWO separate parameter types:

| Parameter Type | YAML Key | Syntax in Statement | When Resolved |
|----------------|----------|---------------------|---------------|
| SQL Parameters | `parameters` | `@p1`, `@p2` | At query execution (parameterized) |
| Template Parameters | `templateParameters` | `{{.varName}}` | Before execution (string substitution) |

---

## What Happens When Templates Fail

When a user configures:

```yaml
run-query:
  kind: mssql-sql
  parameters:          # User puts 'query' here...
    - name: query
      type: string
  statement: "{{.query}}"   # ...but uses template syntax in statement
```

The code flow:

1. `ResolveTemplateParams()` is called with an **empty** `templateParameters` list
2. Template parsing succeeds on `"{{.query}}"`
3. Template execution looks for `.query` in `templateParamsMap` which is **empty**
4. Go's text/template renders missing values as `<no value>`
5. SQL Server receives: `<no value>` instead of the actual query
6. SQL Server error: **"Incorrect syntax near '<'"** (from the `<` in `<no value>`)

---

## Correct vs Incorrect Configuration

### Broken (what the compatibility report shows)

```yaml
run-query:
  kind: mssql-sql
  parameters:                    # WRONG - regular params don't go to template
    - name: query
      type: string
  statement: "{{.query}}"
```

### Correct (per documentation)

Per `genai-toolbox/docs/en/resources/tools/mssql/mssql-sql.md:76-101`:

```yaml
run-query:
  kind: mssql-sql
  templateParameters:            # CORRECT - template params for {{ }} syntax
    - name: query
      type: string
  statement: "{{.query}}"
```

---

## Why mssql-execute-sql Works

The `mssql-execute-sql` kind (`/genai-toolbox/internal/tools/mssql/mssqlexecutesql/mssqlexecutesql.go:98-110`) is fundamentally different:

- It accepts raw SQL directly via a `sql` parameter
- It **does NOT process templates at all**
- The SQL is passed directly to `QueryContext()`

This is why switching to `mssql-execute-sql` in the compatibility report "fixed" the issue - it bypasses template processing entirely.

---

## Code Locations

| Component | File | Lines |
|-----------|------|-------|
| mssql-sql tool | `internal/tools/mssql/mssqlsql/mssqlsql.go` | 101-125 |
| mssql-execute-sql tool | `internal/tools/mssql/mssqlexecutesql/mssqlexecutesql.go` | 98-110 |
| Template resolution | `internal/util/parameters/parameters.go` | 197-219 |
| Documentation | `docs/en/resources/tools/mssql/mssql-sql.md` | 76-101 |

---

## Conclusion

This is a **documentation/usability issue** rather than a code bug. The toolbox requires users to explicitly declare `templateParameters` (not just `parameters`) when using `{{.variable}}` syntax, but this distinction is subtle and easy to miss.

The configurations in the compatibility report are incorrect - they use `parameters` instead of `templateParameters`.

### Recommendation

Update the tools.yaml configuration to use `templateParameters` for any variables using Go template syntax:

```yaml
count-rows:
  kind: mssql-sql
  source: baseline-mssql
  description: Count rows in a table
  templateParameters:              # Changed from 'parameters'
    - name: table_name
      type: string
      description: Name of the table
  statement: |
    SELECT COUNT(*) as row_count FROM {{.table_name}}
```

**Note:** Using `templateParameters` for table names means string interpolation (not parameterized queries), which has SQL injection implications. For user-facing tools, consider using `mssql-execute-sql` with appropriate access controls instead.
