# Runline for Cursor

Runline is a native iOS 26+ client for managing Cursor Cloud Agents from iPhone and iPad.

The app uses a proven Cloud Agents foundation with a chat-first, system-native iOS interface: stock navigation, lists, forms, sheets, toolbars, and settings surfaces.

Runline is independent and is not affiliated with, endorsed by, or connected to Cursor or Anysphere.

## Status

Runline is in public beta. Cloud Agent mode is the default path and works directly from iOS. Cursor SDK mode is optional and requires Runline Bridge on the user's Mac.

## Features

- iOS 26+ SwiftUI app target
- Chat-first Cloud Agents navigation for iPhone and iPad
- Cursor Cloud Agents v1 provider for account, repositories, models, agents, runs, streams, artifacts, archive, unarchive, and delete
- Optional `@cursor/sdk` bridge client for Cursor SDK sessions, MCP profiles, subagents, and multi-turn follow-ups
- Runline Bridge pairing with one-time terminal codes and Keychain-backed bridge tokens
- First-run and Settings runtime selection between Cloud Agent and Cursor SDK defaults
- Native Cursor SDK composer controls for intent, model, MCP profile, image context, and file context
- Keychain-backed Cursor API key storage
- Local cache for account, repositories, models, agents, runs, stream events, artifacts, notification preferences, and launch draft
- Unit tests for Cursor v1 request contracts, SSE parsing, cache persistence, app routing, push payloads, chat event cleanup, file attachment loading, and SDK bridge request mapping

## Cursor SDK Mode

Cloud Agent mode works directly from iOS. Cursor SDK mode is optional and requires Runline Bridge on the user's Mac:

```bash
npm install -g runline-bridge@beta
export CURSOR_API_KEY="replace-with-your-cursor-key"
runline-bridge up
```

Runline Bridge prints the iPhone-reachable URL and pairing instructions. The iOS app stores the bridge token in Keychain after pairing.

## Development

Install bridge dependencies:

```bash
npm --prefix orchestrator install
```

Run bridge checks:

```bash
npm --prefix orchestrator run typecheck
npm --prefix orchestrator run build
```

Run iOS tests:

```bash
xcodebuild test \
  -project Runline.xcodeproj \
  -scheme Runline \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.4.1'
```

## Release Workflow

TestFlight and App Store releases are maintainer-only and are not required for contributors.

Local ASC automation expects a private `Runline` App Store Connect profile in the maintainer's keychain. Keep Apple API keys, signing files, archives, IPAs, and ASC run artifacts out of git.

Run local preflight checks:

```bash
asc workflow run preflight
```

Upload a TestFlight build with an explicit build number:

```bash
asc workflow run testflight BUILD_NUMBER:<next-build-number>
```

Use explicit build numbers so TestFlight stays aligned with the active Runline sequence.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md), [SECURITY.md](SECURITY.md), and [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md).

## License

Runline is released under the [MIT License](LICENSE).
