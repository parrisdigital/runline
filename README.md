# Runline for Cursor

<p align="center">
  <img src="DesignAssets/runline-logo-transparent-1024.png" alt="Runline logo" width="96" height="96">
</p>

Runline is a native iOS 26+ client for Cursor Cloud Agents. It is designed around a simple public-source model: connect a Cursor API key, choose a repository, start a Cloud Agent chat, follow the run, review artifacts, and continue the conversation from iPhone or iPad.

Runline is independent and is not affiliated with, endorsed by, or connected to Cursor or Anysphere.

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

## Project Status

Runline is in public beta.

- iOS app: native SwiftUI app for iOS 26+ and iPadOS 26+.
- Runtime: direct Cursor Cloud Agents API from the device.
- Authentication: user-owned Cursor API keys stored in iOS Keychain.
- TestFlight/App Store Connect releases: maintainer-managed.
- Public source: no hosted backend, no Node service, no private endpoint required.

## What Runline Does

- Stores the user's Cursor API key in iOS Keychain.
- Lists Cursor repositories and models.
- Starts Cursor Cloud Agent runs from a refined native composer.
- Shows Cloud Agent chats with message bubbles, grouped run events, status, artifacts, and pull request links.
- Supports follow-up prompts, files, and images where the Cursor Cloud API accepts them.
- Provides search, iPhone tab navigation, and iPad split-view navigation.
- Supports system appearance, light mode, dark mode, and notification preferences.
- Keeps the non-affiliation disclaimer visible in the app and docs.

## Runtime Model

Runline has one runtime path:

| Mode | Where it runs | Best for | Requirements |
| --- | --- | --- | --- |
| Cloud Agent | Directly from iOS to Cursor Cloud Agents | Repository tasks, follow-ups, artifacts, PR workflows, release checks | Cursor API key |

Runline does not require Node, a Mac relay, a hosted backend, or any Runline server.

## Install the iOS Beta

The iOS beta is distributed through TestFlight by the maintainer. Once installed:

1. Open Runline.
2. Connect a Cursor API key.
3. Select a repository or paste a repository URL.
4. Start a Cloud Agent chat.
5. Continue the run from the chat composer when more context is needed.

Cursor API keys stay on device in Keychain for direct Cloud Agent requests.

## Repository Layout

```text
Runline/                  SwiftUI app source
RunlineTests/             Unit tests for app state, providers, cache, routing, and Cursor API mapping
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
| TestFlight | Runline `1.0 (21)` in beta testing | Requires App Store Connect access |
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
- Cloud Agent requests go directly from iOS to Cursor's Cloud Agents API.
- Runline does not require or ship a backend service.
- Apple signing material, API keys, `.env` files, archives, IPAs, and provisioning profiles must never be committed.

Report vulnerabilities privately through [SECURITY.md](SECURITY.md).

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md), [AGENTS.md](AGENTS.md), [SECURITY.md](SECURITY.md), [SUPPORT.md](SUPPORT.md), [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md), and [Legal/TRADEMARKS.md](Legal/TRADEMARKS.md).
