---
name: tunnel
description: Manage Cloudflare Tunnels to expose local dev environments via HTTPS with Zero Trust protection
user-invocable: true
allowed-tools: Bash, Read, Write, Edit, Glob, Grep
argument-hint: [up|down|status|share|configure|update]
---
<!-- TUNNEL_VERSION: 0.2.0 -->

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
- `update` — Check for and install skill updates from GitHub
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
   - `cloudflared` installed (`which cloudflared`) — if missing, suggest OS-appropriate install (see **Install Suggestions** below)
   - `caddy` installed (`which caddy`) — if missing, suggest OS-appropriate install (see **Install Suggestions** below)

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

3. **Detect local services** by scanning ALL listening TCP ports >= 1024 (project-agnostic):

   On **macOS**:
   ```bash
   lsof -iTCP -sTCP:LISTEN -nP 2>/dev/null | awk '$9 ~ /:[0-9]+$/ { split($9,a,":"); port=a[length(a)]; if (port >= 1024) print port }' | sort -un
   ```

   On **Linux**:
   ```bash
   ss -tlnp 2>/dev/null | awk 'NR>1 { split($4,a,":"); port=a[length(a)]; if (port >= 1024) print port }' | sort -un
   ```

   Detect the OS with `uname -s` and use the appropriate command.

4. **Label detected ports** by checking the current directory for known config files. These are advisory labels only — unmatched ports are labeled `service-<port>`:

   | Config file(s)                | Framework   | Default port |
   |-------------------------------|-------------|-------------|
   | `vite.config.*`               | Vite        | 5173        |
   | `next.config.*`               | Next.js     | 3000        |
   | `angular.json`                | Angular     | 4200        |
   | `nuxt.config.*`               | Nuxt        | 3000        |
   | `svelte.config.*`             | SvelteKit   | 5173        |
   | `remix.config.*`, `remix.env.d.ts` | Remix  | 3000        |
   | `astro.config.*`              | Astro       | 4321        |
   | `gatsby-config.*`             | Gatsby      | 8000        |
   | `manage.py`                   | Django      | 8000        |
   | `app.py` + `flask` in imports | Flask       | 5000        |
   | `main.py` + `uvicorn`/`fastapi` in imports | FastAPI | 8000 |
   | `Gemfile` + `rails` in contents | Rails     | 3000        |
   | `artisan`                     | Laravel     | 8000        |
   | `pom.xml` or `build.gradle*`  | Spring Boot | 8080        |
   | `mix.exs` + `phoenix` in deps | Phoenix    | 4000        |
   | `main.go`, `go.mod`           | Go          | 8080        |
   | `Cargo.toml`                  | Rust        | 8080        |
   | `package.json` with `"start"` | Node.js     | (check for port hints) |

   If a port matches a framework's default, apply that label. Otherwise use `service-<port>`.

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

## Subcommand: `update`

1. Read the current version from the installed SKILL.md:
   ```bash
   grep 'TUNNEL_VERSION' ~/.claude/skills/tunnel/SKILL.md 2>/dev/null | sed 's/.*TUNNEL_VERSION: *//;s/ *-->.*//'
   ```

2. Fetch the latest SKILL.md from GitHub to a temp file:
   ```bash
   curl -fsSL "https://raw.githubusercontent.com/pedrommaiaa/tunnel/main/skill/SKILL.md" -o /tmp/tunnel-skill-latest.md
   ```

3. Read the remote version:
   ```bash
   grep 'TUNNEL_VERSION' /tmp/tunnel-skill-latest.md | sed 's/.*TUNNEL_VERSION: *//;s/ *-->.*//'
   ```

4. Compare versions:
   - If identical → report `Already up to date (v<version>).` and stop.
   - If different → show a summary of what changed (diff line counts), then replace the installed file:
     ```bash
     cp /tmp/tunnel-skill-latest.md ~/.claude/skills/tunnel/SKILL.md
     ```
   - Report: `Updated v<old> → v<new>. Restart Claude Code to use the new version.`

5. Clean up the temp file:
   ```bash
   rm -f /tmp/tunnel-skill-latest.md
   ```

---

## Error Handling

- If `cloudflared` or `caddy` isn't installed, detect the OS and provide the correct install command (see **Install Suggestions** below).
- If a port conflict occurs on :8080, suggest an alternative port and update configs.
- If a process dies unexpectedly, check `~/.tunnel-manager/cloudflared.log` for errors.
- If the tunnel was created but DNS isn't set up, remind the user about the dashboard step.
- Always verify processes are actually running before reporting success.

### Install Suggestions

Detect the OS using `uname -s` and check for package managers. Provide the first matching suggestion:

**cloudflared:**
| OS / Distro | Command |
|---|---|
| macOS | `brew install cloudflare/cloudflare/cloudflared` |
| Debian/Ubuntu | `curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg \| sudo tee /usr/share/keyrings/cloudflare-main.gpg && echo 'deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared $(lsb_release -cs) main' \| sudo tee /etc/apt/sources.list.d/cloudflared.list && sudo apt update && sudo apt install cloudflared` |
| Fedora/RHEL | `sudo dnf copr enable cloudflare/cloudflared && sudo dnf install cloudflared` |
| Arch | `yay -S cloudflared-bin` (AUR) |
| Fallback | Download from https://github.com/cloudflare/cloudflared/releases |

**caddy:**
| OS / Distro | Command |
|---|---|
| macOS | `brew install caddy` |
| Debian/Ubuntu | `sudo apt install -y debian-keyring debian-archive-keyring apt-transport-https curl && curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' \| sudo gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg && curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' \| sudo tee /etc/apt/sources.list.d/caddy-stable.list && sudo apt update && sudo apt install caddy` |
| Fedora/RHEL | `sudo dnf install 'dnf-command(copr)' && sudo dnf copr enable @caddy/caddy && sudo dnf install caddy` |
| Arch | `sudo pacman -S caddy` |
| Fallback | Download from https://caddyserver.com/download |

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
