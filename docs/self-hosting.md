# Self-Hosting Runline Bridge

This guide is for users who want Cursor SDK mode in Runline.

Cloud Agent mode does not need this guide. It works directly from iOS with a Cursor API key stored in Keychain.

Runline Bridge is only required for optional Cursor SDK workflows such as SDK sessions, MCP profiles, and bridge-side tooling.

## What Runs Where

| Component | Runs on | Purpose |
| --- | --- | --- |
| Runline iOS app | iPhone or iPad | Native Cloud Agent and optional SDK remote UI |
| Runline Bridge | Mac or trusted server | Cursor SDK session and MCP profile bridge |
| Cursor Cloud Agents | Cursor infrastructure | Cloud Agent execution |
| Cursor SDK | Bridge environment | Optional SDK session behavior |

The bridge does not need to store user Cursor API keys. Prefer per-request bearer tokens from the iOS app when possible. For local single-user setups, `CURSOR_API_KEY` in the shell environment is also supported.

## Option 1: Simulator Localhost

Use this for local iOS Simulator development.

```bash
cd orchestrator
npm install
npm run build
export CURSOR_API_KEY="replace-with-your-cursor-key"
npm run bridge
```

In the Simulator, set the bridge URL to:

```text
http://localhost:8787
```

Then open Settings in Runline, enable Runline Bridge, and pair.

## Option 2: Physical iPhone on LAN

Use this for a physical iPhone or TestFlight build on the same Wi-Fi network as your Mac.

Install and start the bridge:

```bash
npm install -g runline-bridge
export CURSOR_API_KEY="replace-with-your-cursor-key"
runline-bridge up
```

The bridge binds to `0.0.0.0` by default so it is reachable from a trusted iPhone or iPad on the same network. The terminal prints a `Local URL`, an `iPhone URL`, and a `Runline setup link`. When your terminal supports it, it also prints a QR code that opens Runline and sets the bridge URL automatically. In Runline's Cursor SDK onboarding, use **Scan with QR Code** for the setup QR and **Pair with Code** for the terminal pairing code.

For Mac-assisted Cursor SDK sessions that should continue while you are away from the keyboard, start the bridge with Keep Awake:

```bash
runline-bridge up --keep-awake
```

On macOS this uses `caffeinate` while the bridge process is running. It is disabled by default, stops when the bridge exits, and does not apply to Cloud Agent mode.

Find your Mac's LAN IP:

```bash
ipconfig getifaddr en0
```

If that returns `192.168.1.10`, enter this bridge URL in Runline Settings:

```text
http://192.168.1.10:8787
```

Do not use `localhost` on a physical iPhone. On device, `localhost` points to the phone, not your Mac. Scan the setup QR in Runline onboarding or use the `iPhone URL` printed by `runline-bridge up`.

## Option 3: Tailscale or Private Network

For regular personal use, a private network is usually more stable than plain LAN discovery.

Typical setup:

1. Put your Mac and iPhone on the same Tailscale network.
2. Start `runline-bridge` on the Mac.
3. Use the Mac's Tailscale IP or MagicDNS name as the bridge host.
4. Pair once in Runline Settings.

Example:

```text
http://macbook.tailnet-name.ts.net:8787
```

Use HTTPS if your private-network setup terminates TLS in front of the bridge.

## Option 4: Temporary HTTPS Tunnel

For short beta tests, a temporary tunnel can expose your local bridge through HTTPS.

Example with Cloudflare Tunnel:

```bash
cloudflared tunnel --url http://127.0.0.1:8787
```

Use the generated `https://...trycloudflare.com` URL in Runline Settings.

Treat temporary tunnel URLs as short-lived. Re-pair or update the bridge URL when the tunnel changes.

## Option 5: Hosted HTTPS Bridge

For broader beta usage, use a bridge endpoint that the iPhone can reliably reach over HTTPS.

Recommended properties:

- HTTPS only outside a private network
- no server-side storage of Cursor API keys
- pairing required
- request logging redacts authorization headers and prompts
- health endpoint exposed for status checks
- deployment secrets stored in the host's secret manager

Runline Bridge currently exposes HTTP endpoints. Put a trusted reverse proxy such as Caddy, Nginx, Traefik, or a managed platform in front of it if you need TLS.

## Environment Variables

See [orchestrator/.env.example](../orchestrator/.env.example) for safe placeholders.

Common local variables:

| Variable | Purpose |
| --- | --- |
| `CURSOR_API_KEY` | Optional local Cursor key used when the app does not send a bearer token |
| `RUNLINE_BRIDGE_PORT` | Optional bridge port if supported by the current bridge version |
| `RUNLINE_BRIDGE_HOST` | Optional bind host if supported by the current bridge version |
| `RUNLINE_BRIDGE_DISABLE_PAIRING` | Local development only; disables pairing requirement |
| `RUNLINE_SDK_MCP_PROFILES` | JSON array of public MCP profile metadata and private bridge-side tool config |

Do not commit real values.

## Pairing

By default, Runline Bridge requires pairing.

In Runline:

1. Open Settings.
2. Choose Cursor SDK Setup if needed.
3. Enable Runline Bridge.
4. Enter the bridge URL.
5. Tap Start Pairing.
6. Enter the code printed by the bridge terminal.

The iOS app stores the bridge token in Keychain.

## MCP Profiles

MCP profiles are configured on the bridge and exposed to the iOS app as metadata.

Keep private MCP tokens and server credentials on the bridge side. Do not put them in the iOS app or public source.

Example:

```bash
export RUNLINE_SDK_MCP_PROFILES='[
  {
    "id": "github-tools",
    "name": "GitHub Tools",
    "description": "GitHub MCP plus reviewer subagent.",
    "mcpServers": {
      "github": {
        "command": "npx",
        "args": ["-y", "@modelcontextprotocol/server-github"]
      }
    }
  }
]'
```

## Troubleshooting

### The Simulator works but iPhone cannot connect

Check that the bridge URL uses a Mac LAN, Tailscale, or HTTPS hostname the phone can reach. `localhost` only works in Simulator.

### Pairing starts but completion fails

Check that:

- the code is current
- the bridge URL did not change
- the iPhone and bridge are reaching the same running process
- the bridge was not restarted between start and complete

### The bridge health check fails

Check:

- the bridge process is running
- the selected port is open
- the URL has `http://` or `https://`
- the host is reachable from the phone
- a reverse proxy is forwarding requests correctly

### Cursor SDK mode is unavailable in the app

Runline intentionally falls back to Cloud Agent mode if the bridge is not ready. Open Settings and verify:

- Runline Bridge is enabled
- the bridge URL is valid
- pairing is complete
- connection status is connected

## What Not to Commit

Do not commit:

- Cursor API keys
- `.env`
- `.npmrc`
- private bridge URLs that should not be public
- APNs credentials
- Apple signing material
- App Store Connect live workflow config
- private MCP credentials

See [SELF_HOSTING_MODEL.md](../SELF_HOSTING_MODEL.md) for the public repository boundary.
