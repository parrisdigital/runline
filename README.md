# Runline for Cursor

<p align="center">
  <img src="DesignAssets/runline-logo-transparent-1024.png" alt="Runline logo" width="96" height="96">
</p>

Runline is a native iOS 26+ client for Cursor development on iPhone and iPad. It has two separate experiences: Cursor Chat for SDK-backed conversational workspace sessions, and Cursor Cloud for the structured Cloud Agent workflow.

Runline is independent and is not affiliated with, endorsed by, or connected to Cursor or Anysphere.

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

## Project Status

Runline is in public beta.

- iOS app: native SwiftUI app for iOS 26+ and iPadOS 26+.
- Runtime: Cursor Chat through the Runline SDK bridge, plus direct Cursor Cloud Agents API from the device.
- Authentication: user-owned Cursor API keys stored in iOS Keychain.
- TestFlight/App Store Connect releases: maintainer-managed.
- Public source: Cloud Agent mode requires no hosted backend, Node service, or private endpoint.

## What Runline Does

- Stores the user's Cursor API key in iOS Keychain.
- Lists Cursor repositories and models.
- Starts conversational Cursor Chat sessions from a composer-first screen with repo-backed or general-chat context.
- Tracks Cursor Chat conversations in a slide-over drawer grouped by workspace.
- Continues a General Chat into a repository-backed workspace while carrying the chat topic and prior context.
- Starts Cursor Cloud Agent runs from the structured native Cloud flow.
- Organizes Cursor Cloud into running, review-ready, attention, and archived run queues with compact output indicators.
- Shows Cursor Cloud run-review detail headers with state, repository context, diffs, artifacts, pull requests, and cancel actions.
- Defaults Cursor Cloud and Cursor Chat to Composer 2.5 while preserving explicit model selections.
- Shows agent chats with immediate user bubbles, quiet live activity rows, grouped run events, status, artifacts, and pull request links.
- Shows inline file-change summaries and diff sheets when SDK events include parseable change data.
- Supports follow-up prompts, files, and images, including queued Cursor Chat follow-ups while a run is active.
- Uses the hosted Runline SDK bridge for Cursor Chat, with bridge source included for auditability and maintainer deployment.
- Provides search, iPhone tab navigation, and iPad split-view navigation.
- Supports system appearance, light mode, dark mode, and notification preferences.
- Keeps the non-affiliation disclaimer visible in the app and docs.

## Runtime Model

Runline has two runtime paths. Cursor Cloud remains fully backendless, while Cursor Chat uses the Runline SDK bridge for the more native conversational workspace loop.

| Mode | Where it runs | Best for | Requirements |
| --- | --- | --- | --- |
| Cursor Chat | iOS to the Runline SDK bridge, then `@cursor/sdk` to Cursor cloud runtime | Cursor-like live sessions, SDK event streaming, follow-up iteration | Cursor API key |
| Cursor Cloud | Directly from iOS to Cursor Cloud Agents | Repository tasks, artifacts, PR workflows, release checks | Cursor API key |

Runline does not require Node, a Mac relay, or a user-run backend for Cursor Cloud. Cursor Chat uses the hosted Runline bridge by default, so normal iOS users and contributors do not need to install or run the bridge locally.

## Install the iOS Beta

The iOS beta is distributed through TestFlight by the maintainer. Once installed:

1. Open Runline.
2. Connect a Cursor API key.
3. Select a repository or paste a repository URL.
4. Start a conversational Cursor Chat or a structured Cursor Cloud run.
5. Continue the session from the chat composer when more context is needed.

Cursor API keys stay on device in Keychain. Cursor Cloud uses the key directly from the app; Cursor Chat sends it over HTTPS to the Runline bridge only for SDK-backed requests.

## Cursor Chat Bridge Source

The SDK bridge source is included in `Services/cursor-sdk-bridge` for transparency and maintainer deployment. It is not part of the normal iOS setup path, and contributors do not need npm, Node, Fly, or a local bridge to build and inspect the app.

Bridge deployments should keep live Fly configuration, bridge secrets, and tokens outside git. The service includes `fly.example.toml` only as a public-safe shape for maintainers or advanced self-hosters. The bridge does not persist Cursor API keys or prompt text.

## Repository Layout

```text
Runline/                  SwiftUI app source
RunlineTests/             Unit tests for app state, providers, cache, routing, and Cursor API mapping
Services/cursor-sdk-bridge/
                          Cursor SDK bridge source for auditability and hosted Cursor Chat
DesignAssets/             Public logo and app icon source previews
Legal/                    Trademark and branding guidance
Tools/                    Maintainer utilities such as build-number updates
.asc/                     Sanitized ASC workflow example only; live config is ignored
.github/                  CI, issue templates, PR template, Dependabot
docs/                     Release and roadmap documentation
AGENTS.md                 Operating rules for contributors and coding agents
SELF_HOSTING_MODEL.md     Public repo and source boundary
```

## Development Setup

Requirements:

- macOS
- Xcode 26 or newer with the iOS 26 simulator runtime
- Swift 6
- XcodeGen, if regenerating the Xcode project from `project.yml`

Run iOS tests:

```bash
xcodebuild test \
  -project Runline.xcodeproj \
  -scheme Runline \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.4.1'
```

Run metadata checks:

```bash
xcodebuild -list -project Runline.xcodeproj
ruby -c Tools/set_build_number.rb
plutil -lint ExportOptions-AppStore.plist ExportOptions-TestFlightUpload.plist Runline/Resources/Info.plist Runline/Resources/PrivacyInfo.xcprivacy Runline/Resources/Runline.entitlements
```

Run secret scanning before public release work:

```bash
gitleaks detect --source . --redact --verbose
gitleaks detect --source . --no-git --redact --verbose
```

## Release Channels

| Channel | Current state | Notes |
| --- | --- | --- |
| GitHub | Public repository at `parrisdigital/runline` | Source, docs, issues, releases |
| TestFlight | Runline `1.0 (25)` in beta testing | Requires App Store Connect access |
| App Store | Preparing public publishing | Maintainer-managed |

See [docs/RELEASES.md](docs/RELEASES.md) for the maintainer release checklist, [CHANGELOG.md](CHANGELOG.md) for public release notes, and [docs/ROADMAP.md](docs/ROADMAP.md) for the beta roadmap.

## Maintainer TestFlight Workflow

TestFlight and App Store releases are maintainer-only and are not required for contributors.

Local ASC automation expects a private `Runline` App Store Connect profile in the maintainer's keychain. Keep Apple API keys, signing files, live ASC workflow config, archives, IPAs, and ASC run artifacts out of git.

Use the sanitized example as the starting point for local release work:

```bash
cp .asc/workflow.example.json .asc/workflow.json
```

Then fill in the local App Store Connect app and TestFlight group IDs. The live `.asc/workflow.json` file is ignored by git.

Run local preflight checks:

```bash
asc workflow run preflight
```

Upload a TestFlight build with an explicit build number:

```bash
asc workflow run testflight BUILD_NUMBER:<next-build-number>
```

Use explicit build numbers so TestFlight stays aligned with the active Runline sequence.

## Security Model

- Cursor API keys are stored on iOS in Keychain.
- Cursor Cloud requests go directly from iOS to Cursor's Cloud Agents API.
- Cursor Chat requests send the Cursor API key over HTTPS to the Runline bridge for SDK execution. The bridge is designed not to persist Cursor API keys.
- Users do not need to configure a bridge URL or shared secret for the default Cursor Chat path.
- Apple signing material, API keys, `.env` files, archives, IPAs, and provisioning profiles must never be committed.

Report vulnerabilities privately through [SECURITY.md](SECURITY.md).

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md), [AGENTS.md](AGENTS.md), [SECURITY.md](SECURITY.md), [SUPPORT.md](SUPPORT.md), [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md), and [Legal/TRADEMARKS.md](Legal/TRADEMARKS.md).
