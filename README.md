# Runline for Cursor

Runline is a native iOS 26+ client for managing Cursor Cloud Agents from iPhone.

The app uses a proven Cloud Agents foundation with a chat-first, system-native iOS interface: stock navigation, lists, forms, sheets, toolbars, and settings surfaces.

Runline is independent and is not affiliated with, endorsed by, or connected to Cursor or Anysphere.

## Current Foundation

- iOS 26+ SwiftUI app target
- Chat-first Cloud Agents navigation
- Cursor Cloud Agents v1 provider for account, repositories, models, agents, runs, streams, artifacts, archive, unarchive, and delete
- Optional `@cursor/sdk` bridge client for SDK Agent sessions, MCP profiles, subagents, and multi-turn follow-ups
- Keychain-backed Cursor API key storage
- Local cache for account, repositories, models, agents, runs, stream events, artifacts, notification preferences, and launch draft
- Unit tests for Cursor v1 request contracts, SSE parsing, cache persistence, app routing, push payloads, chat event cleanup, file attachment loading, and SDK bridge request mapping
