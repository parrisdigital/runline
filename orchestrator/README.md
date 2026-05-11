# Runline Bridge

Runline Bridge is the optional Mac-side CLI for Cursor SDK workflows in [Runline for Cursor](https://github.com/parrisdigital/runline).

The iOS app does not depend on this service for the core Cloud Agent path. Runline keeps using Cursor's v1 REST API directly for account, repository, model, agent, run, stream, lifecycle, and artifact basics.

Source package version: `runline-bridge@0.1.6`.
Current published npm package: `runline-bridge@0.1.5`.

Runline is independent and is not affiliated with, endorsed by, or connected to Cursor or Anysphere.

Use this service only for work that benefits from `@cursor/sdk`:

- Resumable Cursor SDK sessions with multi-turn follow-up messages.
- SDK-normalized event streams and conversation state.
- Launch payloads that include MCP server profiles or subagents.
- Service-account workflows for teams.
- Future automation or APNs backend jobs that should not run in the iOS app.

## Install

```bash
npm install -g runline-bridge
runline-bridge up
```

Only install Runline Bridge if you want Cursor SDK mode. Cloud Agent mode in the iOS app works without this package.

Runline sends the Cursor API key from iOS Keychain as a per-request bearer token. `CURSOR_API_KEY` is optional for command-line testing, single-user local setups, or service-owned deployments.

`runline-bridge up` binds to `0.0.0.0` by default so an iPhone on the same trusted network can reach it. The terminal prints:

- `Local URL`, for the Mac and iOS Simulator.
- `iPhone URL`, for physical iPhone and iPad.
- `Runline setup link`, plus a QR code when the terminal supports it.
- a pairing QR/link after the app starts pairing, so the iPhone can complete setup without typing the code.

On a physical iPhone, do not use `http://localhost:8787`. Scan the setup QR or use the printed `iPhone URL`.

To keep your Mac awake while SDK mode is connected:

```bash
runline-bridge up --keep-awake
```

On macOS this uses `caffeinate` while the bridge is running. It is disabled by default and stops when the bridge exits. It does not affect Cloud Agent mode.

Check the installed version:

```bash
runline-bridge --version
```

For LAN, Tailscale, temporary tunnel, and hosted HTTPS bridge setups, see [docs/self-hosting.md](../docs/self-hosting.md).

## Run From This Repo

```bash
cd orchestrator
npm install
npm run build
export CURSOR_API_KEY="replace-with-your-cursor-key"
npm run bridge
```

For Simulator testing, `http://localhost:8787` is usually enough. For a physical iPhone or TestFlight build on the same Wi-Fi network, use your Mac's LAN address instead:

```bash
ipconfig getifaddr en0
```

Then set the app's bridge URL to `http://<mac-lan-ip>:8787`. For broader TestFlight use, deploy the bridge behind HTTPS and use that hosted URL.

The iOS app can also send the user's Cursor API key as a per-request bearer token. Prefer that for user-owned keys; the bridge does not need to store keys server-side.

If you expose the bridge through a tunnel, reverse proxy, Tailscale MagicDNS name, or hosted HTTPS endpoint, pass the externally reachable URL so QR codes contain the address the phone should use:

```bash
runline-bridge up --public-url https://your-bridge.example.com
```

## Pairing

Runline Bridge requires a local pairing token by default. In the iOS app, open the SDK tab or Settings, enable Runline Bridge, enter or scan the bridge URL, and tap **Start Pairing**. The bridge prints a six-digit code and a `runline://bridge?...` pairing QR/link in the terminal. Scan that QR from Runline to complete pairing, or enter the code manually.

The bridge persists issued pairing tokens in `~/.runline-bridge/tokens.json` with owner-only permissions. Override the location with `RUNLINE_BRIDGE_TOKEN_FILE`, or disable persistence with `RUNLINE_BRIDGE_DISABLE_TOKEN_PERSISTENCE=true` if you want every bridge restart to require re-pairing.

For local development only, you can disable pairing:

```bash
export CURSOR_API_KEY="replace-with-your-cursor-key"
RUNLINE_BRIDGE_DISABLE_PAIRING=true runline-bridge up
```

## MCP Profiles

Publish SDK tool profiles with `RUNLINE_SDK_MCP_PROFILES`. The value is a JSON array. Each profile is exposed to iOS as selectable metadata, while private MCP credentials, command environments, hook scripts, and full subagent prompts stay on the bridge.

```bash
export RUNLINE_SDK_MCP_PROFILES='[
  {
    "id": "github-tools",
    "name": "GitHub Tools",
    "description": "GitHub MCP plus reviewer subagent and project skills.",
    "mcpServers": {
      "github": {
        "command": "npx",
        "args": ["-y", "@modelcontextprotocol/server-github"],
        "env": {
          "GITHUB_PERSONAL_ACCESS_TOKEN": "from-your-shell"
        }
      }
    },
    "toolHints": [
      {
        "id": "github-prs",
        "name": "Pull requests",
        "description": "Read, create, and update pull request context.",
        "server": "github"
      }
    ],
    "skills": [
      {
        "id": "review-checklist",
        "name": "Review checklist",
        "description": "Apply project review criteria before execution.",
        "source": ".cursor/skills/review-checklist"
      }
    ],
    "hooks": [
      {
        "id": "preflight",
        "name": "Preflight checks",
        "event": "before_execute",
        "command": "npm test"
      }
    ],
    "agents": {
      "reviewer": {
        "description": "Checks implementation risk and missing tests.",
        "prompt": "Review implementation risk and missing tests."
      }
    }
  }
]'
```

The iOS app displays profile details for:

- MCP servers, transport, auth presence, environment key names, and tool hints.
- Subagents, prompt previews, model inheritance, and server references.
- Cursor skills published by the bridge.
- Hooks published by the bridge.
- Per-chat profile selection for new SDK sessions and follow-up messages.

Runline does not currently edit bridge profile JSON from iOS. That is intentional for the beta: the bridge remains the source of truth for local commands and secrets.

## Endpoints

- `GET /health`
- `POST /pair/start`
- `POST /pair/complete`
- `GET /sdk/mcp-profiles`
- `POST /sdk/sessions`
- `POST /sdk/sessions/:sessionId/messages`
- `GET /sdk/sessions/:sessionId/state?runId=:runId`
- `GET /sdk/sessions/:sessionId/runs/:runId/events`
- `POST /sdk/sessions/:sessionId/runs/:runId/cancel`
- `POST /runs/cloud` compatibility alias for `POST /sdk/sessions`
- `GET /agents/:agentId/runs/:runId/state`
- `GET /agents/:agentId/runs/:runId/events`
- `POST /agents/:agentId/runs/:runId/cancel`

Requests may pass a Cursor API key with bearer authentication. If omitted, the service uses `CURSOR_API_KEY`. Do not put user keys in logs or long-lived storage.

## Environment

Safe placeholders live in [.env.example](.env.example). Do not commit `.env`.

```bash
cp .env.example .env
```

Load the values using your shell or process manager. The bridge does not require dotenv loading by default.

## Package Checks

Run these before publishing:

```bash
npm run typecheck
npm run build
npm audit --audit-level=high
npm pack --dry-run
```

Publish from `orchestrator/`:

```bash
npm version patch --no-git-tag-version
npm publish --tag beta
npm dist-tag add runline-bridge@<version> latest
```

## SDK Session Example

```bash
curl http://localhost:8787/sdk/sessions \
  -H 'Content-Type: application/json' \
  --oauth2-bearer "$CURSOR_API_KEY" \
  -d '{
    "prompt": "Create an implementation plan for the failing tests.",
    "intent": "plan",
    "repositoryUrl": "https://github.com/your-org/your-repo",
    "startingRef": "main",
    "modelId": "composer-2",
    "mcpProfileId": "github-tools",
    "autoCreatePR": true
  }'
```

The response includes `sessionId`, `agentId`, `runId`, `sessionEventsURL`, and `sessionStateURL`.

## Follow-Up Example

```bash
curl http://localhost:8787/sdk/sessions/bc-example/messages \
  -H 'Content-Type: application/json' \
  --oauth2-bearer "$CURSOR_API_KEY" \
  -d '{
    "prompt": "Execute the approved plan.",
    "intent": "execute",
    "mcpProfileId": "github-tools"
  }'
```
