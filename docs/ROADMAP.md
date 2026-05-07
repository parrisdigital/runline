# Roadmap

Runline is in public beta. This roadmap is intentionally practical and may change as TestFlight feedback comes in.

## Near Term

- Keep Cloud Agent mode reliable as the default workflow.
- Continue polishing native iPhone and iPad layouts.
- Improve chat transcript rendering for assistant, thinking, execution, and artifacts.
- Expand attachment handling where the Cursor API and SDK paths support it.
- Tighten Runline Bridge pairing diagnostics and setup copy.

## Cursor SDK Mode

- Keep SDK mode optional and clearly separate from Cloud Agent mode.
- Improve the setup path for users who install `runline-bridge`.
- Add clearer status for local LAN, localhost, and hosted HTTPS bridge URLs.
- Expand MCP profile and subagent display once the bridge contract is stable.

## Release Readiness

- Keep TestFlight builds aligned with explicit build numbers.
- Keep `runline-bridge` npm metadata and dist-tags current.
- Maintain gitleaks, npm audit, CI, and release documentation before major public pushes.

## Not Planned for MVP

- Full source editor or IDE replacement.
- Hosted bridge service operated by default for every user.
- Automatic storage of user Cursor API keys outside the user's device or local bridge environment.
