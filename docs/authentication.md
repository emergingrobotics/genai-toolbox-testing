# Authentication in MCP Toolbox

The toolbox supports authentication through **Auth Services** that validate tokens from clients.

## Supported Auth Methods

Currently only **Google OpenID Connect** is supported. There's no built-in API key support.

## Configuration

### 1. Define an Auth Service

In `tools.yaml`, add an `authServices` section:

```yaml
authServices:
  my-google-auth:
    kind: google
    name: my-google-auth
    clientId: "YOUR_CLIENT_ID.apps.googleusercontent.com"
```

| Field | Description |
|-------|-------------|
| `kind` | Must be `google` (only supported type) |
| `name` | Unique name for this auth service (used in headers) |
| `clientId` | Your Google OAuth 2.0 Client ID |

### 2. Require Auth on Tools

Add `authRequired` to any tool that needs protection:

```yaml
tools:
  list-tables:
    kind: mssql-sql
    source: baseline-mssql
    description: "List all tables (no auth required)"
    statement: "SELECT * FROM INFORMATION_SCHEMA.TABLES"

  secure-query:
    kind: mssql-sql
    source: baseline-mssql
    description: "Query sensitive data (requires auth)"
    statement: "SELECT * FROM sensitive_table"
    authRequired:
      - "my-google-auth"
```

Tools without `authRequired` (or with an empty list) are publicly accessible.

### 3. Client Sends Token in Header

When invoking a protected tool, clients must send the token in a header named `{authServiceName}_token`:

```bash
curl -X POST http://localhost:5001/mcp/ \
  -H "Content-Type: application/json" \
  -H "my-google-auth_token: eyJhbGciOiJSUzI1NiIs..." \
  -d '{
    "jsonrpc": "2.0",
    "id": "1",
    "method": "tools/call",
    "params": {
      "name": "secure-query",
      "arguments": {}
    }
  }'
```

## How Token Validation Works

1. Server receives request with `{authServiceName}_token` header
2. Looks up the auth service by name
3. Validates the JWT token against the configured Google Client ID
4. Extracts user claims (email, sub, iss, etc.)
5. Checks if the tool requires that auth service
6. If verified, allows the tool invocation

## Complete Example

```yaml
authServices:
  google-auth:
    kind: google
    name: google-auth
    clientId: "123456789.apps.googleusercontent.com"

sources:
  prod-db:
    kind: mssql
    host: ${SQLCMDSERVER}
    port: 1433
    database: ${SQLCMDDBNAME}
    user: ${SQLCMDUSER}
    password: ${SQLCMDPASSWORD}

tools:
  # Public tool - no auth required
  list-tables:
    kind: mssql-sql
    source: prod-db
    description: "List all tables"
    statement: |
      SELECT TABLE_SCHEMA, TABLE_NAME
      FROM INFORMATION_SCHEMA.TABLES
      WHERE TABLE_TYPE = 'BASE TABLE'

  # Protected tool - requires Google auth
  query-users:
    kind: mssql-sql
    source: prod-db
    description: "Query user data (requires authentication)"
    authRequired:
      - "google-auth"
    parameters:
      - name: email
        type: string
        description: "User email to look up"
    statement: |
      SELECT * FROM Users WHERE Email = @p1

toolsets:
  default:
    - list-tables
    - query-users
```

## Client OAuth (Alternative)

Some sources (like BigQuery, Looker) support passing through client OAuth tokens. This uses the standard `Authorization: Bearer` header instead of auth services.

```yaml
sources:
  bigquery-source:
    kind: bigquery
    project: my-project
    use_client_oauth: true

tools:
  bq-query:
    kind: bigquery-sql
    source: bigquery-source
    useClientOAuth: true
    statement: "SELECT * FROM dataset.table"
```

**Note:** `authRequired` and `useClientOAuth` are mutually exclusive - you cannot use both on the same tool.

## Multiple Auth Services

A tool can accept authentication from multiple services. If ANY of them validates successfully, access is granted (OR logic):

```yaml
authServices:
  google-auth:
    kind: google
    name: google-auth
    clientId: "google-client-id.apps.googleusercontent.com"

  corp-google-auth:
    kind: google
    name: corp-google-auth
    clientId: "corp-client-id.apps.googleusercontent.com"

tools:
  shared-tool:
    kind: mssql-sql
    source: my-db
    description: "Accessible by either auth service"
    authRequired:
      - "google-auth"
      - "corp-google-auth"
    statement: "SELECT 1"
```

## Tool Manifests

Protected tools expose their auth requirements in the MCP tool manifest:

```json
{
  "name": "secure-query",
  "description": "Query sensitive data (requires auth)",
  "inputSchema": { ... },
  "_meta": {
    "toolbox/authInvoke": ["google-auth"]
  }
}
```

Clients can inspect this to know which tools require authentication.

## Important Notes

- **stdio transport**: Auth is disabled for stdio connections (no header support)
- **No API keys**: Only Google OpenID is currently supported
- **Claims available**: Verified user claims can be passed to tool parameters
- **Header naming**: Token headers must follow the pattern `{serviceName}_token`

## Setting Up Google OAuth

To use Google authentication:

1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Create or select a project
3. Navigate to **APIs & Services > Credentials**
4. Click **Create Credentials > OAuth 2.0 Client IDs**
5. Configure the OAuth consent screen if prompted
6. Select application type (Web application, Desktop app, etc.)
7. Copy the **Client ID** to your `tools.yaml`

## Claude Code Integration

For Claude Code to authenticate with protected tools, it would need to:

1. Obtain a Google OpenID token (via OAuth flow)
2. Send the token in the appropriate header with each request

This typically requires custom MCP client configuration. For local development and testing, it's simpler to omit `authRequired` from your tools.

## Troubleshooting

### "unauthorized" error

- Verify the token header name matches `{authServiceName}_token`
- Check that the token is a valid Google ID token
- Ensure the Client ID in config matches the one used to generate the token

### Token not being validated

- Confirm the auth service name in `authRequired` matches the `name` field in `authServices`
- Check server logs for validation errors

### Claims not available

- Verify the token was generated with the correct scopes
- Check that the auth service validated successfully before the tool was invoked
