# Google OpenID Connect Setup for MCP Server Authentication

This guide walks through obtaining Google OAuth 2.0 / OpenID Connect credentials to authenticate with an MCP server (such as Google MCP Toolbox).

## Prerequisites

- A Google account
- Access to [Google Cloud Console](https://console.cloud.google.com/)
- A project in Google Cloud (or permission to create one)

## Step 1: Create or Select a Google Cloud Project

1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Click the project dropdown in the top navigation bar
3. Either select an existing project or click **New Project**
4. If creating new:
   - Enter a project name
   - Select an organization (if applicable)
   - Click **Create**

## Step 2: Enable Required APIs

1. Navigate to **APIs & Services** → **Library**
2. Search for and enable:
   - **Google Identity Toolkit API** (for authentication)
   - Any other APIs your MCP toolbox requires (e.g., Gmail API, Calendar API, Drive API)

## Step 3: Configure the OAuth Consent Screen

Before creating credentials, you must configure the consent screen:

1. Go to **APIs & Services** → **OAuth consent screen**
2. Select User Type:
   - **Internal**: Only users in your Google Workspace org (if applicable)
   - **External**: Any Google account user
3. Click **Create**
4. Fill in the required fields:
   - **App name**: Your application name (e.g., "MCP Toolbox Client")
   - **User support email**: Your email
   - **Developer contact information**: Your email
5. Click **Save and Continue**

### Add Scopes

1. Click **Add or Remove Scopes**
2. Add the scopes your MCP server requires. Common ones include:
   - `openid` — Required for OIDC
   - `email` — Access to user's email address
   - `profile` — Access to basic profile info
   - Service-specific scopes (e.g., `https://www.googleapis.com/auth/gmail.readonly`)
3. Click **Update** then **Save and Continue**

### Add Test Users (External apps only)

If your app is "External" and not yet verified:

1. Click **Add Users**
2. Add the Google accounts that will use this during testing
3. Click **Save and Continue**

## Step 4: Create OAuth 2.0 Credentials

1. Go to **APIs & Services** → **Credentials**
2. Click **Create Credentials** → **OAuth client ID**
3. Select Application type based on your MCP client:

### For Desktop/CLI Applications (most common for MCP)

- Application type: **Desktop app**
- Name: Something descriptive (e.g., "MCP Toolbox CLI")
- Click **Create**

### For Web Applications

- Application type: **Web application**
- Name: Your app name
- **Authorized JavaScript origins**: Add your app's origin (e.g., `http://localhost:3000`)
- **Authorized redirect URIs**: Add callback URLs (e.g., `http://localhost:3000/callback`)
- Click **Create**

## Step 5: Download and Store Credentials

After creation, a dialog shows your credentials:

1. **Client ID**: `xxxx.apps.googleusercontent.com`
2. **Client Secret**: Keep this secret!

Options:

- Click **Download JSON** to get a `credentials.json` file
- Or copy the values to your configuration

Store the JSON file securely:

```bash
# Create a config directory
mkdir -p ~/.config/mcp-toolbox

# Move and protect the credentials file
mv ~/Downloads/client_secret_*.json ~/.config/mcp-toolbox/credentials.json
chmod 600 ~/.config/mcp-toolbox/credentials.json
```

## Step 6: Configure Your MCP Client

The exact configuration depends on your MCP client. Common patterns:

### Environment Variables

```bash
export GOOGLE_CLIENT_ID="your-client-id.apps.googleusercontent.com"
export GOOGLE_CLIENT_SECRET="your-client-secret"
```

### Configuration File

```json
{
  "auth": {
    "provider": "google",
    "client_id": "your-client-id.apps.googleusercontent.com",
    "client_secret": "your-client-secret",
    "scopes": ["openid", "email", "profile"]
  }
}
```

### Using the JSON Credentials File

Some clients accept the path to the downloaded JSON:

```bash
export GOOGLE_APPLICATION_CREDENTIALS="$HOME/.config/mcp-toolbox/credentials.json"
```

## Step 7: First Authentication Flow

When you first connect to the MCP server:

1. The client initiates an OAuth flow
2. A browser window opens to Google's login page
3. Sign in with your Google account
4. Review and accept the requested permissions
5. Google redirects back with an authorization code
6. The client exchanges this for access/refresh tokens
7. Tokens are typically cached locally for future use

### Token Storage Location

Tokens are usually stored in:

```
~/.config/mcp-toolbox/token.json
# or
~/.cache/mcp-toolbox/token.json
```

## Troubleshooting

### "Access blocked: This app's request is invalid"

- Verify redirect URIs match exactly (including trailing slashes)
- Check that you're using the correct client ID

### "This app isn't verified"

- For testing, click **Advanced** → **Go to [App Name] (unsafe)**
- For production, submit your app for verification

### "Insufficient Permission"

- Add required scopes to OAuth consent screen
- Re-authenticate to get new tokens with updated scopes

### Token Refresh Issues

```bash
# Remove cached tokens to force re-authentication
rm ~/.config/mcp-toolbox/token.json
```

## Security Best Practices

1. **Never commit credentials** to version control
2. **Use environment variables** or secure secret management
3. **Restrict API access** to only required scopes
4. **Rotate secrets** periodically
5. **Monitor usage** via Google Cloud Console → APIs & Services → Metrics

## Quick Reference: Common Google API Scopes

| Scope | Description |
|-------|-------------|
| `openid` | Basic OIDC authentication |
| `email` | User's email address |
| `profile` | Basic profile (name, picture) |
| `https://www.googleapis.com/auth/gmail.readonly` | Read Gmail |
| `https://www.googleapis.com/auth/calendar.readonly` | Read Calendar |
| `https://www.googleapis.com/auth/drive.readonly` | Read Drive files |

## References

- [Google OAuth 2.0 Documentation](https://developers.google.com/identity/protocols/oauth2)
- [OpenID Connect on Google](https://developers.google.com/identity/openid-connect/openid-connect)
- [Google API Scopes](https://developers.google.com/identity/protocols/oauth2/scopes)
