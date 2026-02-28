---
name: tunnel
description: Manage Cloudflare Tunnels to expose local dev environments via HTTPS with Zero Trust protection
user-invocable: true
allowed-tools: Bash, Read, Write, Edit, Glob, Grep
argument-hint: [up|down|status|share|configure]
---

# Tunnel Manager

You are managing Cloudflare Tunnels to expose local dev environments as production-like HTTPS URLs with Cloudflare Zero Trust (Access) protection.

## Architecture

```
Local dev servers → Caddy reverse proxy (:8080) → cloudflared tunnel → https://dev.domain.com
                                                                            ↓
                                                                   Cloudflare Access (login gate)
```

## Arguments

Parse `$ARGUMENTS` to determine the subcommand:

- `up` — Start tunnel (detect services, generate configs, launch)
- `down` — Stop tunnel (kill caddy + cloudflared processes)
- `status` — Show running tunnels, URLs, and process health
- `share <email>` — Add a user to the Access policy (requires CF API token)
- `configure` — Interactively set up tunnel name, domain, and credentials
- (no argument) — Show help/usage

---

## State File

All persistent state lives in `~/.tunnel-manager/state.json`. Read it at the start of every invocation. Create it on first use.

Schema:
```json
{
  "configured": false,
  "tunnel_name": "",
  "tunnel_uuid": "",
  "domain": "",
  "credentials_file": "",
  "cf_api_token": "",
  "caddy_pid": null,
  "cloudflared_pid": null,
  "services": []
}
```

---

## Subcommand: `configure`

Run this on first use or when the user wants to reconfigure.

1. Check prerequisites:
   - `cloudflared` installed (`which cloudflared`) — if missing, tell user to run `brew install cloudflare/cloudflare/cloudflared`
   - `caddy` installed (`which caddy`) — if missing, tell user to run `brew install caddy`

2. Ask the user for:
   - **Tunnel name** (default: derived from hostname, e.g. `macbook-dev`)
   - **Domain** (e.g. `dev.yourdomain.com`) — must be a domain on their Cloudflare account

3. Check if `cloudflared` is authenticated:
   - Look for `~/.cloudflared/cert.pem`
   - If missing, tell the user to run `cloudflared tunnel login` and wait for them to confirm

4. Create the tunnel:
   ```bash
   cloudflared tunnel create <tunnel-name>
   ```
   Parse the output to extract the tunnel UUID.

5. Find the credentials file:
   ```bash
   ls ~/.cloudflared/*.json
   ```
   Match the UUID from step 4.

6. Save everything to `~/.tunnel-manager/state.json`.

7. Tell the user they need to set up the public hostname in the Cloudflare dashboard:
   - Zero Trust → Networks → Tunnels → <tunnel-name> → Public Hostnames
   - Add hostname: `<domain>`, service: `http://localhost:8080`
   - Enable "Protect with Access" and create a policy (allow their email)

---

## Subcommand: `up`

1. Read `~/.tunnel-manager/state.json`. If not configured, run `configure` first.

2. Check if already running (PIDs in state file, verify with `kill -0 <pid>`). If so, report status instead.

3. **Detect local services** by scanning common dev ports:
   ```bash
   lsof -iTCP -sTCP:LISTEN -nP 2>/dev/null | grep -E ':(3000|3001|4000|4200|5000|5173|5174|8000|8080|8888) '
   ```

4. **Detect project stack** by checking the current directory for:
   - `vite.config.*` → Vite (likely :5173)
   - `next.config.*` → Next.js (likely :3000)
   - `angular.json` → Angular (likely :4200)
   - `package.json` with `"start"` script → check for port hints
   - `manage.py` → Django (likely :8000)
   - `main.go`, `go.mod` → Go (likely :8080)
   - `Cargo.toml` → Rust (varies)

5. **Ask the user** to confirm the detected services or provide custom ones. Services are an array of `{ name, port, path_prefix }`:
   - Default: frontend on detected port at `/`, backend on detected port at `/api/*`
   - If only one service detected, route everything to it (no Caddy needed)

6. **Generate Caddyfile** at `~/.tunnel-manager/Caddyfile`:
   ```caddy
   :8080

   @api path /api/*
   reverse_proxy @api localhost:3000

   reverse_proxy localhost:5173
   ```
   Adapt the matchers based on the confirmed services. If websocket support is needed (Vite HMR, Next.js, etc.), add:
   ```caddy
   @ws {
       header Connection *Upgrade*
       header Upgrade websocket
   }
   ```

7. **Generate cloudflared config** at `~/.tunnel-manager/config.yml`:
   ```yaml
   tunnel: <tunnel-name>
   credentials-file: <credentials-file-path>

   ingress:
     - hostname: <domain>
       service: http://localhost:8080
     - service: http_status:404
   ```
   If only one service (no Caddy), point directly to that port.

8. **Start Caddy** (if multiple services):
   ```bash
   caddy start --config ~/.tunnel-manager/Caddyfile --pidfile ~/.tunnel-manager/caddy.pid
   ```
   Save PID to state.

9. **Start cloudflared**:
   ```bash
   nohup cloudflared tunnel --config ~/.tunnel-manager/config.yml run > ~/.tunnel-manager/cloudflared.log 2>&1 &
   echo $!
   ```
   Save PID to state.

10. **Verify** — wait 3 seconds, check both processes are alive, then report:
    ```
    Tunnel is up!
    URL: https://<domain>
    Services:
      / → localhost:5173 (frontend)
      /api/* → localhost:3000 (backend)
    Caddy PID: <pid>
    Cloudflared PID: <pid>
    ```

---

## Subcommand: `down`

1. Read state file.
2. Kill Caddy: `caddy stop` or `kill <caddy_pid>`.
3. Kill cloudflared: `kill <cloudflared_pid>`.
4. Verify processes are dead.
5. Update state file (clear PIDs).
6. Report: `Tunnel stopped.`

---

## Subcommand: `status`

1. Read state file.
2. If not configured: report "Not configured. Run `/tunnel configure` first."
3. Check process liveness for stored PIDs.
4. Check if tunnel domain resolves: `curl -sI https://<domain> 2>/dev/null | head -5`
5. Report:
   ```
   Tunnel: <tunnel-name>
   URL: https://<domain>
   Caddy: running (PID <pid>) | stopped
   Cloudflared: running (PID <pid>) | stopped
   Services: <list>
   ```

---

## Subcommand: `share <email>`

1. This requires a Cloudflare API token with Access permissions.
2. If no token in state, ask the user for one and save it.
3. Use the CF API to add an Access policy:
   ```bash
   curl -X POST "https://api.cloudflare.com/client/v4/accounts/<account_id>/access/apps" \
     -H "Authorization: Bearer <token>" \
     -H "Content-Type: application/json" \
     --data '...'
   ```
4. Note: This is the most complex subcommand. If the user hasn't set up Access via the dashboard yet, guide them to do it manually and explain what to click. Only use the API if they've provided a token and account ID.

---

## Error Handling

- If `cloudflared` or `caddy` isn't installed, provide the exact `brew install` command.
- If a port conflict occurs on :8080, suggest an alternative port and update configs.
- If a process dies unexpectedly, check `~/.tunnel-manager/cloudflared.log` for errors.
- If the tunnel was created but DNS isn't set up, remind the user about the dashboard step.
- Always verify processes are actually running before reporting success.

---

## Important Notes

- Never store secrets in plain text except in `~/.tunnel-manager/state.json` (user's local machine only).
- The Caddyfile and config.yml are regenerated on every `up` — they're not meant to be hand-edited.
- If the user has a project-level `.tunnel.json`, prefer its settings over auto-detection:
  ```json
  {
    "services": [
      { "name": "frontend", "port": 5173, "path": "/" },
      { "name": "api", "port": 3000, "path": "/api/*" }
    ]
  }
  ```
- Keep all output concise. No walls of text. Report what happened and the URL.
