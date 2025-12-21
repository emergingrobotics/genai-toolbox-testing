# Authentication Options for genai-toolbox (MCP Toolbox for Databases)

## TL;DR

**genai-toolbox only supports Google OIDC for its built-in auth.** But you likely don't need it for local/dev use.

## The Good News: Auth is Optional

The `authServices` configuration in genai-toolbox is **optional**. If you don't configure any auth, the toolbox server runs without authentication. This is perfectly fine for:

- Local development
- Internal/trusted networks
- Proof-of-concept work
- Behind a reverse proxy that handles auth

## Running Without Authentication

Just don't include the `authServices` section in your `tools.yaml`:

```yaml
# tools.yaml - no auth required
sources:
  my-pg-source:
    kind: postgres
    host: 127.0.0.1
    port: 5432
    database: toolbox_db
    user: toolbox_user
    password: ${DB_PASSWORD}

tools:
  search-hotels:
    kind: postgres-sql
    source: my-pg-source
    description: Search for hotels by name
    parameters:
      - name: name
        type: string
        description: Hotel name to search
    statement: SELECT * FROM hotels WHERE name ILIKE '%' || $1 || '%';
```

Run it:

```bash
./toolbox --tools-file tools.yaml
```

Connect to it (Python example):

```python
from toolbox_core import ToolboxClient

async with ToolboxClient("http://127.0.0.1:5000") as client:
    tools = await client.load_toolset()
```

**That's it.** No OAuth, no tokens, no Google Cloud Console setup.

## When You DO Need Auth

The `authServices` feature is specifically for:

1. **Authorized Invocation**: Rejecting tool calls from unauthenticated users
2. **Authenticated Parameters**: Auto-populating tool parameters from OIDC claims (e.g., injecting the user's email from their token)

If you don't need either of these, skip auth entirely.

## Alternative: External Auth via Reverse Proxy

If you need *some* auth but don't want Google OIDC, put a reverse proxy in front of toolbox:

### nginx with Basic Auth

```nginx
# /etc/nginx/sites-available/toolbox
server {
    listen 8080;
    
    location / {
        auth_basic "MCP Toolbox";
        auth_basic_user_file /etc/nginx/.htpasswd;
        
        proxy_pass http://127.0.0.1:5000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
    }
}
```

Create the password file:

```bash
sudo htpasswd -c /etc/nginx/.htpasswd myuser
```

### Caddy with Basic Auth

```caddyfile
:8080 {
    basicauth {
        myuser $2a$14$... # bcrypt hash from: caddy hash-password
    }
    reverse_proxy 127.0.0.1:5000
}
```

### Traefik with Basic Auth

```yaml
# docker-compose.yml
services:
  traefik:
    image: traefik:v2.10
    command:
      - "--providers.docker=true"
      - "--entrypoints.web.address=:8080"
    ports:
      - "8080:8080"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock

  toolbox:
    image: us-central1-docker.pkg.dev/database-toolbox/toolbox/toolbox:0.24.0
    labels:
      - "traefik.http.routers.toolbox.rule=Host(`localhost`)"
      - "traefik.http.routers.toolbox.middlewares=auth"
      - "traefik.http.middlewares.auth.basicauth.users=myuser:$$apr1$$..."
```

## Alternative: SSH Tunnel (Zero Config)

SSH tunneling lets you securely access a remote toolbox server without configuring any authentication in the toolbox itself. This is ideal for **testing and development** when you already have SSH access to the remote server.

### How It Works

An SSH tunnel creates an encrypted connection between your local machine and the remote server. When you run the tunnel command, SSH:

1. Listens on a port on your local machine (e.g., `localhost:5000`)
2. Encrypts all traffic and forwards it through the SSH connection
3. Delivers it to a port on the remote server (e.g., `localhost:5000` on that server)

Your MCP client thinks it's talking to a local server, but the traffic is actually going to the remote machine over an encrypted SSH connection. Authentication happens via your SSH keys (or password) - the toolbox server itself doesn't need any auth configured.

### Setup

**Terminal 1 - Start the SSH tunnel:**

```bash
# Run this on your LOCAL machine (laptop/workstation)
ssh -L 5000:localhost:5000 user@remote-server.example.com

# -L 5000:localhost:5000 means:
#   - Listen on local port 5000
#   - Forward to localhost:5000 on the remote server
#
# This opens an SSH session. Keep this terminal open.
```

**Terminal 2 - Use the toolbox:**

```bash
# On your LOCAL machine, connect as if the server were local
curl http://localhost:5000/api/toolset

# Or configure Claude Code
claude mcp add --transport sse toolbox-db http://localhost:5000/mcp/sse
```

**Note:** If you're already running a local toolbox on port 5000, use a different local port for the tunnel:

```bash
# Tunnel to local port 5001 instead
ssh -L 5001:localhost:5000 user@remote-server.example.com

# Then connect to localhost:5001
curl http://localhost:5001/api/toolset
```

### Authentication

SSH tunnels use your existing SSH authentication:

- **SSH keys** (recommended): If you have `~/.ssh/id_rsa` or `~/.ssh/id_ed25519` set up with the remote server, no password is needed
- **Password**: SSH will prompt for your password if keys aren't configured
- **SSH agent**: If using `ssh-agent`, your keys are used automatically

No additional credentials are stored or transmitted - it's the same auth you use for regular SSH access.

### When to Use This

| Use Case | SSH Tunnel Appropriate? |
|----------|------------------------|
| Testing against a remote dev server | Yes |
| Temporary access during development | Yes |
| Sharing with teammates | No (each person needs SSH access) |
| Production deployment | No (use proper auth or VPN) |
| Automated/CI pipelines | No (use service accounts or tokens) |

### Keeping the Tunnel Open

For long-running tunnels, use these options to prevent disconnection:

```bash
# Keep connection alive with ServerAliveInterval
ssh -L 5000:localhost:5000 -o ServerAliveInterval=60 user@remote-server

# Run in background (add -f -N)
ssh -f -N -L 5000:localhost:5000 user@remote-server
# -f: background after authentication
# -N: don't execute a remote command (just forward ports)
```

### Multiple Ports

If you need to forward multiple services:

```bash
ssh -L 5000:localhost:5000 -L 5432:localhost:5432 user@remote-server
```

## Alternative: Tailscale/WireGuard (Network-Level Auth)

Put both client and server on the same Tailscale/WireGuard network. The network itself provides authentication.

```bash
# Server (run toolbox bound to Tailscale IP)
./toolbox --tools-file tools.yaml --address 100.x.y.z

# Client connects via Tailscale IP
# Only authenticated Tailscale users can reach it
```

## If You Really Need Google OIDC

See the companion doc on setting up Google OpenID Connect. It requires:

1. Google Cloud project
2. OAuth consent screen configuration
3. OAuth 2.0 Client ID credentials
4. Client-side token handling in your SDK code

## MCP Inspector Note

When using MCP Inspector for testing, you'll see:

```
🔑 Session token: <YOUR_SESSION_TOKEN>
Use this token to authenticate requests or set DANGEROUSLY_OMIT_AUTH=true to disable auth
```

This is MCP Inspector's own auth, **not genai-toolbox auth**. For local testing, you can set `DANGEROUSLY_OMIT_AUTH=true` in your environment.

## Summary

| Scenario | Solution |
|----------|----------|
| Local dev | No auth needed, just run it |
| Internal network | No auth, or basic auth via proxy |
| Remote access | SSH tunnel or VPN |
| Need user identity in queries | Google OIDC (only option) |
| Production internet-facing | Google OIDC or proxy + your own auth |

For most local/dev work: **just skip auth entirely**.
