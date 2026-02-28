# claude-tunnel

A [Claude Code](https://claude.com/claude-code) skill that exposes your local dev environment as a production-like HTTPS URL using Cloudflare Tunnels + Zero Trust.

No port forwarding. No IP exposure. One URL that works from anywhere, protected by login.

## Prerequisites

- [Claude Code](https://claude.com/claude-code)
- [cloudflared](https://github.com/cloudflare/cloudflared) — `brew install cloudflare/cloudflare/cloudflared`
- [caddy](https://caddyserver.com/) — `brew install caddy`
- A domain managed by Cloudflare (nameservers pointing to Cloudflare)

## Cloudflare Setup (one-time)

Before using the skill, you need to configure a few things in Cloudflare. This only needs to be done once.

### 1. Add your domain to Cloudflare

If you don't already have a domain on Cloudflare:

1. Go to [Cloudflare Dashboard](https://dash.cloudflare.com/)
2. Click **Add a site** and enter your domain
3. Select the **Free** plan
4. Cloudflare will give you two nameservers — update your domain registrar to use them
5. Wait for nameserver propagation (can take a few minutes to 24 hours)

### 2. Enable Cloudflare Zero Trust

1. In the Cloudflare Dashboard, click **Zero Trust** in the left sidebar
2. Follow the prompts to create a Zero Trust organization (free for up to 50 users)
3. Pick a team name (e.g. `yourname-dev`)

### 3. Authenticate your machine

Run this in your terminal:

```bash
cloudflared tunnel login
```

This opens a browser window. Select your domain and authorize. This saves a certificate to `~/.cloudflared/cert.pem` that lets your machine create tunnels.

### 4. Create the tunnel

Run `/tunnel configure` in Claude Code (see [Usage](#usage) below) — it will create the tunnel for you. Or do it manually:

```bash
cloudflared tunnel create laptop-dev
```

This creates a tunnel and saves a credentials JSON file to `~/.cloudflared/<TUNNEL-UUID>.json`.

### 5. Add a public hostname to the tunnel

1. Go to **Zero Trust → Networks → Tunnels**
2. Click on your tunnel (e.g. `laptop-dev`)
3. Go to the **Public Hostnames** tab
4. Click **Add a public hostname**
5. Fill in:
   - **Subdomain**: `dev` (or whatever you want)
   - **Domain**: select your domain from the dropdown
   - **Service type**: `HTTP`
   - **URL**: `localhost:8080`
6. Click **Save hostname**

Your tunnel will now route `https://dev.yourdomain.com` → `localhost:8080`.

### 6. Protect with Cloudflare Access

This ensures only authorized users can access your dev URL.

**Option A — Protect directly on the tunnel hostname (easiest):**

1. In the same **Public Hostname** entry from step 5
2. Toggle **Protect with Access**
3. Create a policy:
   - **Policy name**: e.g. `Allow me`
   - **Action**: Allow
   - **Include rule**: Emails — enter your email
4. Save

**Option B — Create an Access Application:**

1. Go to **Zero Trust → Access → Applications**
2. Click **Add an application → Self-hosted**
3. **Application domain**: `dev.yourdomain.com`
4. **Session duration**: pick what you like (e.g. 24 hours)
5. Create a policy:
   - **Policy name**: e.g. `Allow me`
   - **Action**: Allow
   - **Include rule**: Emails — enter your email
6. Save

Now anyone visiting `https://dev.yourdomain.com` will be prompted to log in through Cloudflare Access before they can reach your local server.

## Install the Skill

```bash
curl -fsSL https://raw.githubusercontent.com/pedromaia/claude-tunnel/main/install.sh | bash
```

Or clone and run locally:

```bash
git clone https://github.com/pedromaia/claude-tunnel.git
cd claude-tunnel
./install.sh
```

The installer copies the skill to `~/.claude/skills/tunnel/` and creates `~/.tunnel-manager/` for state. Restart Claude Code after installing.

## Usage

Open Claude Code and type:

```
/tunnel configure    # First-time setup (tunnel name, domain, credentials)
/tunnel up           # Detect services, generate configs, start tunnel
/tunnel down         # Stop caddy + cloudflared
/tunnel status       # Check tunnel health, URLs, running processes
/tunnel share email  # Add someone to the Access policy
```

### Typical workflow

```bash
# First time only
/tunnel configure
# → asks for tunnel name and domain
# → saves credentials to ~/.tunnel-manager/state.json

# Every time you want to expose your dev environment
/tunnel up
# → detects running services (e.g. Vite on :5173, Express on :3000)
# → generates Caddyfile (/ → frontend, /api/* → backend)
# → starts caddy + cloudflared
# → prints: https://dev.yourdomain.com

# When you're done
/tunnel down
```

## How it works

```
localhost:5173 (frontend) ─┐
                           ├→ Caddy (:8080) → cloudflared → https://dev.yourdomain.com
localhost:3000 (backend)  ─┘                                        │
                                                            Cloudflare Access
                                                            (login required)
```

The skill auto-detects your stack (Vite, Next.js, Angular, Django, Go, etc.) and generates the routing config automatically.

### Custom routing

For projects that need specific routing, add a `.tunnel.json` to your project root:

```json
{
  "services": [
    { "name": "frontend", "port": 5173, "path": "/" },
    { "name": "api", "port": 3000, "path": "/api/*" }
  ]
}
```

When present, the skill uses this instead of auto-detection.

### Single service

If only one service is detected, the tunnel points directly to that port — Caddy is skipped entirely.

## What you get

- **No port forwarding** — the tunnel is outbound-only, your router config is untouched
- **No IP exposure** — Cloudflare proxies everything, your home IP stays hidden
- **HTTPS URL** — works like production, no certificate hassle
- **Access gate** — login required, configurable per-user with MFA
- **One URL** — test on phone, share with a colleague, works from anywhere

## Uninstall

```bash
./uninstall.sh
```

Or manually:

```bash
rm -rf ~/.claude/skills/tunnel ~/.tunnel-manager
```

To also delete the tunnel from Cloudflare:

```bash
cloudflared tunnel delete <tunnel-name>
```

And remove the public hostname from Zero Trust → Networks → Tunnels.

## License

MIT
