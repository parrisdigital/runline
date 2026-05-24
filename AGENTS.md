# Agent and Contributor Operating Rules

This file is for human contributors and coding agents working in the Runline repository.

## Project Boundary

Runline is a native iOS app with two separate Cursor development experiences: SDK-backed Cursor Chat and direct Cursor Cloud.

- Cursor Cloud talks directly from iOS to Cursor Cloud Agents and remains the backendless fallback.
- The app must keep working without Node, a hosted backend, or any local companion service.
- Official builds may include a maintainer-configured Cursor Chat bridge endpoint, and advanced deployments may use a self-hosted `Services/cursor-sdk-bridge` Node service.
- Normal iOS development must not require npm, Node, Fly, or a local bridge install.
- API keys stay in Keychain on iOS.
- In Cursor Cloud, the Cursor API key is used only for direct Cursor API requests.
- In Cursor Chat, the Cursor API key may be sent over HTTPS to the configured SDK bridge for SDK execution. Do not persist it on the bridge.

Runline is independent and is not affiliated with, endorsed by, or connected to Cursor or Anysphere.

## Security Rules

Never commit:

- Cursor API keys
- `.env` or `.npmrc`
- Apple API keys
- `.p8`, `.p12`, `.cer`, `.pem`, `.key`, `.mobileprovision`, or `.provisionprofile`
- generated `.ipa` or `.xcarchive` files
- `.asc/workflow.json`
- APNs credentials
- private MCP credentials
- Fly tokens, bridge shared secrets, or private deployment config
- private bridge URLs or build settings that point at live infrastructure
- generated Node artifacts such as `node_modules/` or `Services/*/dist/`

Only `.asc/workflow.example.json` is safe to track for App Store Connect workflow shape.
Only `Services/cursor-sdk-bridge/fly.example.toml` is safe to track for Fly deployment shape.

Before public-facing commits, run:

```bash
git diff --check
gitleaks detect --source . --redact --verbose
```

For deeper public-release checks, also run:

```bash
gitleaks detect --source . --no-git --redact --verbose
xcodebuild test -project Runline.xcodeproj -scheme Runline -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.4.1'
```

## iOS Rules

- Keep the UI native SwiftUI and system-pattern first.
- Preserve iPhone and iPad layouts.
- Preserve system, light, and dark appearance behavior.
- Keep Settings as the place where users can change API keys, notifications, appearance, and advanced API access.
- Keep API keys in Keychain.
- Keep the non-affiliation disclaimer visible where appropriate.

## Cursor Cloud and SDK Rules

- Do not log Cursor API keys, prompts, file contents, artifact URLs, or private repository data.
- Prefer the existing `CursorAPIClient`, `CursorAgentProvider`, and domain models over new network paths.
- Prefer `CursorSDKBridgeProvider` and `SDKBridgeClient` for Cursor Chat behavior instead of adding parallel SDK bridge clients.
- Do not add undocumented Cursor API calls for public behavior unless they are guarded and documented as experimental.

## Documentation Rules

When changing public behavior, update the relevant docs:

- [README.md](README.md)
- [CHANGELOG.md](CHANGELOG.md)
- [SELF_HOSTING_MODEL.md](SELF_HOSTING_MODEL.md)
- [docs/RELEASES.md](docs/RELEASES.md)

Do not document private maintainer IDs, private signing configuration, private release credentials, or private endpoints.

## Release Rules

- Use explicit TestFlight build numbers.
- Keep live ASC config local and ignored.
- Do not attach IPAs, archives, signing files, or ASC artifacts to public GitHub releases.
- Run the release checklist in [docs/RELEASES.md](docs/RELEASES.md).
