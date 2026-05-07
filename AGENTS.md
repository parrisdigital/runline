# Agent and Contributor Operating Rules

This file is for human contributors and coding agents working in the Runline repository.

## Project Boundary

Runline has two runtime modes:

- Cloud Agent mode: direct iOS calls to Cursor Cloud Agents. This must keep working without Node, Runline Bridge, or a hosted backend.
- Cursor SDK mode: optional power-user path through Runline Bridge.

Do not make Cloud Agent mode depend on the bridge.

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
- private bridge URLs that should not be public
- private MCP credentials

Only `.asc/workflow.example.json` and `orchestrator/.env.example` are safe to track.

Before public-facing commits, run:

```bash
git diff --check
gitleaks detect --source . --redact --verbose
```

For deeper public-release checks, also run:

```bash
gitleaks detect --source . --no-git --redact --verbose
npm --prefix orchestrator run typecheck
npm --prefix orchestrator run build
npm --prefix orchestrator audit --audit-level=high
xcodebuild test -project Runline.xcodeproj -scheme Runline -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.4.1'
```

## iOS Rules

- Keep the UI native SwiftUI and system-pattern first.
- Preserve iPhone and iPad layouts.
- Preserve system, light, and dark appearance behavior.
- Keep Settings as the place where users can change runtime mode, bridge URL, pairing, notifications, and appearance.
- Keep API keys and bridge tokens in Keychain.
- Keep the non-affiliation disclaimer visible where appropriate.

## Bridge Rules

- Keep `runline-bridge` optional.
- Do not log Cursor API keys, bearer tokens, prompts, file contents, or pairing tokens.
- Prefer per-request bearer tokens for user-owned keys.
- Keep private MCP config bridge-side.
- Keep `.env.example` generic.
- Keep npm package metadata pointed at `parrisdigital/runline`.

## Documentation Rules

When changing public behavior, update the relevant docs:

- [README.md](README.md)
- [CHANGELOG.md](CHANGELOG.md)
- [SELF_HOSTING_MODEL.md](SELF_HOSTING_MODEL.md)
- [docs/self-hosting.md](docs/self-hosting.md)
- [docs/RELEASES.md](docs/RELEASES.md)
- [orchestrator/README.md](orchestrator/README.md)

Do not document private maintainer IDs, private hosted endpoints, private signing configuration, or private release credentials.

## Release Rules

- Use explicit TestFlight build numbers.
- Keep live ASC config local and ignored.
- Do not attach IPAs, archives, signing files, or ASC artifacts to public GitHub releases.
- Keep npm dist-tags intentional.
- Run the release checklist in [docs/RELEASES.md](docs/RELEASES.md).
