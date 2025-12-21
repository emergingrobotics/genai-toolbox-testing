You need to create a `tools.yaml` file in your current directory that defines your SQL Server connection and the tools you want to expose.

Here's a minimal example for MS SQL Server:

```yaml
sources:
  my-mssql-source:
    kind: mssql
    host: your-server-hostname-or-ip
    port: 1433
    database: your_database
    user: ${MSSQL_USER}
    password: ${MSSQL_PASSWORD}
    # encrypt: true  # uncomment for Azure SQL or if you require encryption

tools:
  list-tables:
    kind: mssql-list-tables
    source: my-mssql-source
    description: List all tables in the database

  run-query:
    kind: mssql-execute-sql
    source: my-mssql-source
    description: Run a SQL query against the database

  search-by-query:
    kind: mssql-sql
    source: my-mssql-source
    description: Search for records using a custom query
    parameters:
      - name: query
        type: string
        description: The SQL query to execute
    statement: "{{.query}}"

toolsets:
  default:
    - list-tables
    - run-query
    - search-by-query
```

Then run with environment variables for credentials:

```bash
export VERSION=0.24.0
export MSSQL_USER=your_username
export MSSQL_PASSWORD=your_password

podman run -p 5001:5000 \
  -e MSSQL_USER \
  -e MSSQL_PASSWORD \
  -v $(pwd)/tools.yaml:/app/tools.yaml:Z \
  us-central1-docker.pkg.dev/database-toolbox/toolbox/toolbox:$VERSION \
  --tools-file "/app/tools.yaml" \
  --address "0.0.0.0"
```

## A safer example with parameterized queries

Instead of allowing arbitrary SQL, you can define specific tools:

```yaml
sources:
  my-mssql-source:
    kind: mssql
    host: sql-server.example.com
    port: 1433
    database: AdventureWorks
    user: ${MSSQL_USER}
    password: ${MSSQL_PASSWORD}

tools:
  list-tables:
    kind: mssql-list-tables
    source: my-mssql-source
    description: List all tables in the database

  search-customers:
    kind: mssql-sql
    source: my-mssql-source
    description: Search for customers by name
    parameters:
      - name: name
        type: string
        description: Customer name to search for
    statement: |
      SELECT TOP 100 * 
      FROM Customers 
      WHERE CustomerName LIKE '%' + @p1 + '%'

  get-orders-by-date:
    kind: mssql-sql
    source: my-mssql-source
    description: Get orders within a date range
    parameters:
      - name: start_date
        type: string
        description: Start date (YYYY-MM-DD)
      - name: end_date
        type: string
        description: End date (YYYY-MM-DD)
    statement: |
      SELECT TOP 100 *
      FROM Orders
      WHERE OrderDate BETWEEN @p1 AND @p2
      ORDER BY OrderDate DESC

toolsets:
  default:
    - list-tables
    - search-customers
    - get-orders-by-date
```

## Reference

For all available SQL Server tool kinds and options, see:
https://googleapis.github.io/genai-toolbox/resources/sources/mssql/
