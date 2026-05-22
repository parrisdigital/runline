# Agent and Contributor Operating Rules

This file is for human contributors and coding agents working in the Runline repository.

## Project Boundary

Runline is a Cursor Cloud-only iOS app.

- The iOS app talks directly to Cursor Cloud Agents.
- The app must keep working without Node, a hosted backend, or any local companion service.
- API keys stay in Keychain and are used only for direct Cursor API requests.

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

Only `.asc/workflow.example.json` is safe to track for App Store Connect workflow shape.

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

## Cursor Cloud Rules

- Do not log Cursor API keys, prompts, file contents, artifact URLs, or private repository data.
- Prefer the existing `CursorAPIClient`, `CursorAgentProvider`, and domain models over new network paths.
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
