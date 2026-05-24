# Cursor SDK Capability Notes

Verified on 2026-05-24 from Cursor's official SDK launch material and official `cursor/plugins` SDK skill references.

## Current Facts

- `@cursor/sdk` latest on npm is `1.0.13`, which matches the bridge lockfile.
- The SDK is TypeScript-first and exposes `Agent.prompt`, `Agent.create`, `agent.send`, `Agent.resume`, `Agent.get`, `Agent.getRun`, streaming, waiting, cancellation, artifacts, models, repositories, and account identity.
- The SDK supports local and cloud runtimes. Runline should keep using cloud mode through the Fly bridge because the iOS app cannot run the TypeScript SDK or local tool executor directly.
- Cloud SDK sessions use Cursor's Cloud Agents infrastructure: dedicated VM, repo clone when a repo is supplied, streaming/reconnect, branch/PR output, artifacts, and resumable agent IDs.
- Streaming emits structured event types such as `assistant`, `thinking`, `tool_call`, `status`, `task`, `user`, `system`, and `request`. The UI should keep rendering these as compact chat activity, not raw expandable logs by default.
- `run.wait()` is still required even when consuming `run.stream()`, because the stream is observation and `wait()` returns final status, duration, usage/git metadata, and terminal result.
- MCP servers can be passed inline with `mcpServers` on both local and cloud runtimes. HTTP/SSE MCP auth is proxied by Cursor's backend for cloud; stdio MCP env vars run inside the cloud VM.
- Inline MCP servers do not persist across `Agent.resume`; the bridge must pass them again on resume or rely on dashboard/team/project/plugin configuration.
- Cursor's official materials say cloud agents pick up MCP, skills, hooks, and subagents from the Cursor harness. Repo skills live under `.cursor/skills`; hooks live under `.cursor/hooks.json`.
- Custom subagents are cloud-only in the current SDK reference and are passed through the `agents` field.
- Cursor plugins are marketplace bundles that may contain skills, rules, and MCP configuration. The SDK does not expose a mobile "install plugin" API in the verified materials; Runline should treat plugins as Cursor-side configuration unless we later add explicit bridge support around SDK `mcpServers`/`agents`.
- Slash commands such as `/sdk` are Cursor product UI affordances. The verified SDK surface is `Agent.*`, `Run.*`, `Cursor.*`, `mcpServers`, hooks, skills, and subagents; do not design Runline around invoking slash commands as an API.

## Runline Product Decisions

- Keep Cursor Chat as the SDK-backed live conversation surface.
- Keep Cursor Cloud as the direct REST Cloud Agent surface.
- Store Cursor Chat conversation previews and titles on device so completed chats are retrievable even if the bridge returns sparse metadata.
- Keep bridge session persistence metadata-only: session IDs, Cursor agent IDs, run IDs, repo/model metadata, run status, timing, PR/artifact metadata. Do not persist Cursor API keys or prompt text on the bridge.
- Add future UI for MCP/subagents only after the bridge exposes a safe schema for named MCP tools and named subagents.
- Prefer Cursor dashboard/project/team/plugin configuration for end-user tools first; add explicit Runline-managed connectors only when there is a clear mobile UX for credentials and per-workspace scope.

## Sources

- Cursor SDK launch: https://cursor.com/blog/typescript-sdk
- Cursor SDK changelog: https://cursor.com/changelog/sdk-release
- Official Cursor SDK plugin source: https://github.com/cursor/plugins/tree/main/cursor-sdk
- SDK MCP reference: https://raw.githubusercontent.com/cursor/plugins/main/cursor-sdk/skills/cursor-sdk/references/mcp.md
- SDK advanced reference: https://raw.githubusercontent.com/cursor/plugins/main/cursor-sdk/skills/cursor-sdk/references/advanced.md
- SDK streaming reference: https://raw.githubusercontent.com/cursor/plugins/main/cursor-sdk/skills/cursor-sdk/references/streaming.md
- SDK runtime reference: https://raw.githubusercontent.com/cursor/plugins/main/cursor-sdk/skills/cursor-sdk/references/runtime-choice.md
