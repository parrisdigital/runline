# Runline for Cursor

Runline is a native iOS 26+ client for managing Cursor Cloud Agents from iPhone.

The app uses a proven Cloud Agents foundation with a chat-first, system-native iOS interface: stock navigation, lists, forms, sheets, toolbars, and settings surfaces.

Runline is independent and is not affiliated with, endorsed by, or connected to Cursor or Anysphere.

## Current Foundation

- iOS 26+ SwiftUI app target
- Chat-first Cloud Agents navigation
- Cursor Cloud Agents v1 provider for account, repositories, models, agents, runs, streams, artifacts, archive, unarchive, and delete
- Optional `@cursor/sdk` bridge client for Cursor SDK sessions, MCP profiles, subagents, and multi-turn follow-ups
- First-run and Settings runtime selection between Cloud Agent and Cursor SDK defaults
- Native Cursor SDK composer controls for intent, model, MCP profile, image context, and file context
- Keychain-backed Cursor API key storage
- Local cache for account, repositories, models, agents, runs, stream events, artifacts, notification preferences, and launch draft
- Unit tests for Cursor v1 request contracts, SSE parsing, cache persistence, app routing, push payloads, chat event cleanup, file attachment loading, and SDK bridge request mapping

## Release Workflow

ASC is configured through the local `Runline` keychain profile. Release automation lives in `.asc/workflow.json`.

Validate the workflow:

```bash
asc workflow validate
asc workflow list
```

Run local release checks:

```bash
asc workflow run preflight
```

Upload the next TestFlight build with an explicit build number:

```bash
asc workflow run testflight BUILD_NUMBER:11
```

Use explicit build numbers so release numbering stays aligned with the active Runline sequence. The current release target is `1.0 (11)`.
