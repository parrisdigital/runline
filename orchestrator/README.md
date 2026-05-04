# Runline Orchestrator Spike

This is an optional TypeScript backend spike for Cursor SDK-only workflows. The iOS app does not depend on this service for the MVP path; Runline keeps using Cursor's v1 REST API directly for account, repository, model, agent, run, stream, lifecycle, and artifact basics.

Use this service only for work that benefits from `@cursor/sdk`:

- SDK-normalized event streams and conversation turns.
- Launch payloads that include inline MCP server profiles or subagents.
- Service-account workflows for teams.
- Future automation or APNs backend jobs that should not run in the iOS app.

## Run Locally

```bash
cd orchestrator
npm install
CURSOR_API_KEY=your-cursor-key npm run dev
```

## Endpoints

- `GET /health`
- `POST /runs/cloud`
- `GET /agents/:agentId/runs/:runId/state`
- `GET /agents/:agentId/runs/:runId/events`

Requests may pass a Cursor API key with `Authorization: Bearer <key>`. If omitted, the service uses `CURSOR_API_KEY`. Do not put user keys in logs or long-lived storage.

## Cloud Run Example

```bash
curl http://localhost:8787/runs/cloud \
  -H 'Content-Type: application/json' \
  -H 'Authorization: Bearer YOUR_CURSOR_API_KEY' \
  -d '{
    "prompt": "Fix the failing tests and summarize the commands you ran.",
    "repositoryUrl": "https://github.com/your-org/your-repo",
    "startingRef": "main",
    "modelId": "composer-2",
    "autoCreatePR": true
  }'
```

The response includes `agentId`, `runId`, and the local SSE URL for streaming SDK events through the orchestrator.
