# Basic Auth Proxy for MCP Toolbox

This directory contains an nginx-based reverse proxy that adds HTTP Basic Authentication in front of the MCP Toolbox server. Use this when you want simple username/password protection without configuring Google OIDC.

## Architecture

```
┌──────────────┐     ┌─────────────────┐     ┌─────────────────┐
│  MCP Client  │────▶│  nginx Proxy    │────▶│  MCP Toolbox    │
│  (Claude,    │     │  (port 8080)    │     │  (port 5001)    │
│   Agent)     │     │  Basic Auth     │     │  No Auth        │
└──────────────┘     └─────────────────┘     └─────────────────┘
```

The proxy:
- Listens on port **8080**
- Requires username/password for all requests
- Forwards authenticated requests to the MCP Toolbox on port **5001**
- Handles SSE (Server-Sent Events) connections properly

## Prerequisites

- Podman installed
- MCP Toolbox server running on port 5001 (see `../server/scripts/run.sh`)

## Quick Start

### Step 1: Start the MCP Toolbox Server

First, make sure the MCP Toolbox server is running. Open a terminal and run:

```bash
cd /path/to/genai-toolbox-testing
./server/scripts/run.sh
```

You should see output like:
```
INFO "Server ready to serve!"
```

Leave this terminal running.

### Step 2: Start the Basic Auth Proxy

Open a **new terminal** and run:

```bash
cd /path/to/genai-toolbox-testing/basic-auth
./start.sh
```

The script will:
1. **Prompt for credentials** (first run only): Enter a username and password. These will be saved to `.htpasswd` in this directory.
2. **Build the nginx container image**
3. **Start the proxy** on port 8080

Example first-run output:
```
=== MCP Toolbox Basic Auth Proxy ===

No .htpasswd file found. Let's create one.

Enter username: myuser
Enter password for user 'myuser':
Adding password for user myuser
Created .htpasswd file

Building nginx proxy image...
...
Starting proxy container...

=== Proxy is running! ===

Proxy URL:    http://localhost:8080
MCP SSE:      http://localhost:8080/mcp/sse
```

### Step 3: Test the Proxy

Verify the proxy is working:

```bash
# Without credentials - should fail with 401 Unauthorized
curl http://localhost:8080/
# Response: <html>..401 Authorization Required...</html>

# With credentials - should succeed
curl -u myuser:mypassword http://localhost:8080/
# Response: 🧰 Hello, World! 🧰

# Test the API endpoint
curl -u myuser:mypassword http://localhost:8080/api/toolset
# Response: {"serverVersion":"0.24.0",...}
```

### Step 4: Configure Your MCP Client

#### Option A: Claude Code

Add the MCP server with credentials embedded in the URL:

```bash
claude mcp add --transport sse toolbox-db http://myuser:mypassword@localhost:8080/mcp/sse
```

Verify it's connected:

```bash
claude mcp list
# Should show: toolbox-db: http://myuser:mypassword@localhost:8080/mcp/sse (SSE) - ✓ Connected
```

#### Option B: Python Agent

Modify the MCP URL to include credentials:

```bash
export MCP_URL="http://myuser:mypassword@localhost:8080/mcp/sse"
cd ../python-agent
uv run python agent.py
```

Or edit `agent.py` directly:

```python
agent = MCPToolboxAgent(
    mcp_url="http://myuser:mypassword@localhost:8080/mcp/sse",
    ...
)
```

#### Option C: Manual JSON Configuration

Add to `.mcp.json` in your project root:

```json
{
  "mcpServers": {
    "toolbox-db": {
      "type": "sse",
      "url": "http://myuser:mypassword@localhost:8080/mcp/sse"
    }
  }
}
```

## Managing Users

### Add a New User

```bash
# If htpasswd is installed locally
htpasswd .htpasswd newuser

# Or use openssl
read -s PASSWORD && echo "newuser:$(openssl passwd -apr1 $PASSWORD)" >> .htpasswd
```

After adding users, restart the proxy:

```bash
podman restart mcp-basic-auth-proxy
```

### Change a Password

```bash
htpasswd .htpasswd existinguser
podman restart mcp-basic-auth-proxy
```

### Remove a User

Edit `.htpasswd` and delete the line containing the username, then restart:

```bash
podman restart mcp-basic-auth-proxy
```

### View Current Users

```bash
cat .htpasswd
# Output shows usernames and password hashes:
# myuser:$apr1$xyz...
# anotheruser:$apr1$abc...
```

## Proxy Management

### View Logs

```bash
# Follow logs in real-time
podman logs -f mcp-basic-auth-proxy

# View last 50 lines
podman logs --tail 50 mcp-basic-auth-proxy
```

### Stop the Proxy

```bash
podman stop mcp-basic-auth-proxy
```

### Restart the Proxy

```bash
podman restart mcp-basic-auth-proxy
```

### Remove the Proxy Completely

```bash
podman stop mcp-basic-auth-proxy
podman rm mcp-basic-auth-proxy
```

## Troubleshooting

### "502 Bad Gateway" Error

The proxy cannot reach the MCP Toolbox server. Check:

1. Is the MCP Toolbox running?
   ```bash
   curl http://localhost:5001/
   # Should return: 🧰 Hello, World! 🧰
   ```

2. Is it running on port 5001? The proxy expects the toolbox on port 5001, not 5000.

3. On Linux, `host.containers.internal` may not resolve. Edit `nginx.conf` and change:
   ```nginx
   upstream toolbox {
       server 172.17.0.1:5001;  # Docker bridge IP
   }
   ```
   Or use `--network=host` when running the proxy.

### "401 Unauthorized" When Credentials Are Correct

1. Check the `.htpasswd` file exists and has content:
   ```bash
   cat .htpasswd
   ```

2. Verify the file is mounted correctly:
   ```bash
   podman exec mcp-basic-auth-proxy cat /etc/nginx/auth/.htpasswd
   ```

3. Check for special characters in password - some need URL encoding:
   - `@` → `%40`
   - `:` → `%3A`
   - `/` → `%2F`

### SSE Connection Drops

If long-running SSE connections are dropping:

1. Check nginx timeout settings in `nginx.conf`:
   ```nginx
   proxy_read_timeout 86400s;
   proxy_send_timeout 86400s;
   ```

2. Rebuild and restart the proxy:
   ```bash
   podman stop mcp-basic-auth-proxy
   podman rm mcp-basic-auth-proxy
   ./start.sh
   ```

### Claude Code Shows "Failed to Connect"

1. Verify the proxy is running:
   ```bash
   podman ps | grep mcp-basic-auth-proxy
   ```

2. Test the connection manually:
   ```bash
   curl -u myuser:mypassword http://localhost:8080/mcp/sse
   # Should return SSE event stream
   ```

3. Check if credentials in the URL are correct:
   ```bash
   claude mcp list
   # Verify the URL shows correct username:password
   ```

4. Remove and re-add the MCP server:
   ```bash
   claude mcp remove toolbox-db
   claude mcp add --transport sse toolbox-db http://myuser:mypassword@localhost:8080/mcp/sse
   ```

## Security Notes

- **Credentials in URLs**: While convenient, embedding credentials in URLs may expose them in logs. For production, consider using environment variables or a secrets manager.

- **HTTPS**: This proxy uses HTTP. For production, add TLS termination or put this behind another proxy that handles HTTPS.

- **Password Storage**: The `.htpasswd` file contains hashed passwords (not plaintext), but should still be protected. It's listed in `.gitignore` to prevent accidental commits.

- **Network Exposure**: By default, the proxy binds to all interfaces. In production, consider binding to localhost only or using firewall rules.

## Files

| File | Description |
|------|-------------|
| `Dockerfile` | Builds the nginx container image |
| `nginx.conf` | nginx configuration with proxy and auth settings |
| `start.sh` | Script to create credentials and start the proxy |
| `.htpasswd` | Generated file containing username:password hashes (not in git) |
| `README.md` | This file |
