
The commands are essentially identical - just replace `docker` with `podman`:

## Pull the container image

```bash
# see releases page for other versions
export VERSION=0.24.0
podman pull us-central1-docker.pkg.dev/database-toolbox/toolbox/toolbox:$VERSION
```

## Run the server

```bash
export VERSION=0.24.0
podman run -p 5001:5000 \
  -v $(pwd)/tools.yaml:/app/tools.yaml:Z \
  us-central1-docker.pkg.dev/database-toolbox/toolbox/toolbox:$VERSION \
  --tools-file "/app/tools.yaml" \
  --address "0.0.0.0"
```

**Important:** The `--address "0.0.0.0"` flag is required so the server listens on all interfaces inside the container, making it accessible via the port mapping.

**Note:** I added the `:Z` suffix to the volume mount. On SELinux-enabled systems (Fedora, RHEL, CentOS), this tells podman to relabel the volume content so the container can access it. If you're on a non-SELinux system (Debian, Ubuntu, macOS), you can omit it:

```bash
-v $(pwd)/tools.yaml:/app/tools.yaml \
```

If you're running rootless podman and hit permission issues, you might also need `:z` (lowercase) for shared volumes or adjust with `--userns=keep-id`.
