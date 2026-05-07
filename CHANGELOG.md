# Changelog

All notable public changes to Runline are tracked here.

Runline is in public beta. Versions may move quickly while the iOS app, TestFlight flow, and optional Cursor SDK bridge settle.

## Unreleased

- Keep Cloud Agent mode as the default iOS experience.
- Continue refining Cursor SDK mode and Runline Bridge pairing for power users.
- Improve iPhone and iPad polish while staying native to SwiftUI and iOS system patterns.

## Runline Public Beta

- Renamed the project and repository to Runline.
- Prepared GitHub source release `v1.0.0-beta.1`.
- Moved the public repository to `https://github.com/parrisdigital/runline`.
- Preserved the App Store bundle identifier `com.matthewparris.runline`.
- Added open source project files: MIT license, security policy, contributing guide, support guide, code of conduct, issue templates, PR template, Dependabot, CI, and gitleaks configuration.
- Added native iPhone and iPad support for Cloud Agent chats, repositories, Settings, attachments, model selection, light/dark mode, and optional Cursor SDK mode.
- Cleaned chat event rendering so streaming text and thinking deltas are grouped into readable timeline entries.

## runline-bridge 0.1.2

- Published `runline-bridge@0.1.2` to npm.
- Set both `latest` and `beta` npm dist-tags to `0.1.2`.
- Updated npm metadata to point to `parrisdigital/runline`.
- Preserved Cursor SDK session endpoints, pairing endpoints, MCP profile metadata, and Cloud compatibility aliases.
- Added dependency overrides and shrinkwrap updates so the local bridge audit passes with no high-severity findings.

## runline-bridge 0.1.1

- Prepared the bridge package for public beta usage.
- Added repository, homepage, bugs, license, keywords, and packaged README metadata.
- Tightened npm package contents to the CLI, compiled output, README, and shrinkwrap.

## runline-bridge 0.1.0

- Initial bridge package for optional Cursor SDK sessions.
- Added local server, health check, pairing, SDK session creation, follow-up messages, session state, and event endpoints.

## TestFlight Build 1.0 (6)

- Historical TestFlight prerelease retained on GitHub as `testflight-1.0-6`.
- Included iPad adaptive layout work and native iPhone/iPad validation.

## Notes

Runline is independent and is not affiliated with, endorsed by, or connected to Cursor or Anysphere.
